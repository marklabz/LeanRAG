import json
import os
import numpy as np
from pymilvus import MilvusClient
import ollama
import pymysql
from collections import Counter
import yaml
from huggingface_hub import InferenceClient
import logging
import re

# Load config
with open('config.yaml', 'r') as file:
    config = yaml.safe_load(file)

EMBEDDING_PROVIDER = config['embedding']['provider']
HF_MODEL = config['huggingface']['model']
HF_TOKEN = config['huggingface']['HF_TOKEN']

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def validate_database_name(dbname):
    """
    Validate database name to ensure it's safe for MySQL.
    Returns sanitized database name.
    """
    if not dbname:
        return "leanrag_default"
    
    # Remove invalid characters and ensure it starts with a letter or underscore
    sanitized = re.sub(r'[^a-zA-Z0-9_]', '_', dbname)
    if not sanitized[0].isalpha() and sanitized[0] != '_':
        sanitized = 'db_' + sanitized
    
    # MySQL database name max length is 64 characters
    if len(sanitized) > 64:
        sanitized = sanitized[:64]
    
    return sanitized


def get_mysql_connection(dbname=None, create_db=False):
    """
    Create MySQL connection with better error handling.
    
    Args:
        dbname: Database name to connect to
        create_db: Whether to create the database if it doesn't exist
    
    Returns:
        pymysql.Connection object
    """
    try:
        if create_db or not dbname:
            # Connect without database to create it first
            connection = pymysql.connect(
                host='localhost', 
                port=4321, 
                user='root',
                passwd='123', 
                charset='utf8mb4'
            )
            
            if dbname and create_db:
                cursor = connection.cursor()
                validated_dbname = validate_database_name(dbname)
                cursor.execute(f"CREATE DATABASE IF NOT EXISTS {validated_dbname} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
                connection.commit()
                cursor.close()
                connection.close()
                
                # Reconnect to the specific database
                connection = pymysql.connect(
                    host='localhost', 
                    port=4321, 
                    user='root',
                    passwd='123', 
                    database=validated_dbname,
                    charset='utf8mb4'
                )
        else:
            validated_dbname = validate_database_name(dbname)
            connection = pymysql.connect(
                host='localhost', 
                port=4321, 
                user='root',
                passwd='123', 
                database=validated_dbname,
                charset='utf8mb4'
            )
        
        logger.info(f"Successfully connected to MySQL database: {dbname or 'default'}")
        return connection
        
    except pymysql.Error as e:
        logger.error(f"Failed to connect to MySQL: {e}")
        logger.error("Make sure MySQL container is running. Use: ./mysql-docker.sh start")
        raise
    except Exception as e:
        logger.error(f"Unexpected error connecting to MySQL: {e}")
        raise


def emb_text(text):
    """Embedding function that supports both Ollama and HuggingFace providers."""
    if EMBEDDING_PROVIDER == "hf-inference":
        # Use HuggingFace cloud inference
        client = InferenceClient(
            provider="hf-inference",
            api_key=HF_TOKEN,
        )

        # Use feature extraction to get embeddings
        result = client.feature_extraction(
            text=text,
            model=HF_MODEL
        )
        # The result is a list of floats representing the embedding vector
        if isinstance(result, list) and len(result) > 0:
            return result
        else:
            raise ValueError("Failed to get embedding from HuggingFace")

    else:  # Default to Ollama
        response = ollama.embeddings(model="bge-m3:latest", prompt=text)
        return response["embedding"]


def build_vector_search(data, working_dir):

    milvus_client = MilvusClient(uri=f"{working_dir}/milvus_demo.db")
    index_params = milvus_client.prepare_index_params()

    index_params.add_index(
        field_name="dense",
        index_name="dense_index",
        index_type="IVF_FLAT",
        metric_type="IP",
        params={"nlist": 128},
    )

    collection_name = "entity_collection"
    if milvus_client.has_collection(collection_name):
        milvus_client.drop_collection(collection_name)
    milvus_client.create_collection(
        collection_name=collection_name,
        dimension=1024,
        index_params=index_params,
        metric_type="IP",  # Inner product distance
        # Supported values are (`"Strong"`, `"Session"`, `"Bounded"`, `"Eventually"`). See https://milvus.io/docs/consistency.md#Consistency-Level for more details.
        consistency_level="Strong",
    )
    id = 0
    flatten = []
    print("dealing data level")
    for level, sublist in enumerate(data):
        if type(sublist) is not list:
            item = sublist
            item['id'] = id
            id += 1
            item['level'] = level
            if len(item['vector']) == 1:
                item['vector'] = item['vector'][0]
            flatten.append(item)
        else:
            for item in sublist:
                item['id'] = id
                id += 1
                item['level'] = level
                if len(item['vector']) == 1:
                    item['vector'] = item['vector'][0]
                flatten.append(item)
        print(level)
        # embedding = emb_text(description)

    piece = 10

    for indice in range(len(flatten)//piece + 1):
        start = indice * piece
        end = min((indice + 1) * piece, len(flatten))
        data_batch = flatten[start:end]
        milvus_client.insert(
            collection_name="entity_collection",
            data=data_batch
        )
    # milvus_client.insert(
    #         collection_name=collection_name,
    #         data=data
    #     )


def search_vector_search(working_dir, query, topk=10, level_mode=2):
    '''
    level_mode: 0: 原始节点
                1: 聚合节点
                2: 所有节点
    '''
    if level_mode == 0:
        filter_filed = " level == 0 "
    elif level_mode == 1:
        filter_filed = " level > 0 "
    # elif level_mode==2:
    #     filter_filed=" level < 58736"
    else:
        filter_filed = ""
    dataset = os.path.basename(working_dir)
    if os.path.exists(f"{working_dir}/milvus_demo.db"):
        print(f"{working_dir}/milvus_demo.db already exists, using it")
        milvus_client = MilvusClient(uri=f"{working_dir}/milvus_demo.db")
    else:
        print("milvus_demo.db not found, creating new one")
        # Create the milvus database in the working directory
        milvus_client = MilvusClient(uri=f"{working_dir}/milvus_demo.db")
    collection_name = "entity_collection"
    # query_embedding = emb_text(query)
    search_results = milvus_client.search(
        collection_name=collection_name,
        data=[query],
        limit=topk,
        params={"metric_type": "IP", "params": {}},
        filter=filter_filed,
        output_fields=["entity_name", "description",
                       "parent", "level", "source_id"],
    )
    # print(search_results)
    extract_results = [(i['entity']['entity_name'], i["entity"]["parent"], i["entity"]
                        ["description"], i["entity"]["source_id"])for i in search_results[0]]
    # print(extract_results)
    return extract_results


def create_db_table_mysql(working_dir):
    """
    Create MySQL database and tables with improved error handling and logging.
    """
    logger.info(f"Creating database tables for working directory: {working_dir}")
    
    # Handle case where working_dir ends with slash
    clean_path = working_dir.rstrip('/')
    dbname = os.path.basename(clean_path)
    validated_dbname = validate_database_name(dbname)
    
    logger.info(f"Using database name: {validated_dbname}")
    
    try:
        # Create database and get connection
        con = get_mysql_connection(validated_dbname, create_db=True)
        cur = con.cursor()

        # Drop and create entities table
        cur.execute("DROP TABLE IF EXISTS entities")
        entities_sql = """
        CREATE TABLE entities (
            entity_name TEXT, 
            description TEXT, 
            source_id TEXT,
            degree INT,
            parent TEXT,
            level INT
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        """
        cur.execute(entities_sql)
        logger.info("Created entities table")

        # Drop and create relations table  
        cur.execute("DROP TABLE IF EXISTS relations")
        relations_sql = """
        CREATE TABLE relations (
            src_tgt TEXT, 
            tgt_src TEXT, 
            description TEXT,
            weight INT,
            level INT
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        """
        cur.execute(relations_sql)
        logger.info("Created relations table")

        # Drop and create communities table
        cur.execute("DROP TABLE IF EXISTS communities")
        communities_sql = """
        CREATE TABLE communities (
            entity_name TEXT, 
            entity_description TEXT, 
            findings TEXT
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        """
        cur.execute(communities_sql)
        logger.info("Created communities table")
        
        con.commit()
        cur.close()
        con.close()
        
        logger.info(f"Successfully created database tables for: {validated_dbname}")
        
    except Exception as e:
        logger.error(f"Error creating database tables: {e}")
        raise


def insert_data_to_mysql(working_dir):
    """
    Insert data to MySQL with improved error handling and logging.
    """
    logger.info(f"Inserting data to MySQL for working directory: {working_dir}")
    
    # Handle case where working_dir ends with slash
    clean_path = working_dir.rstrip('/')
    dbname = os.path.basename(clean_path)
    validated_dbname = validate_database_name(dbname)
    
    try:
        db = get_mysql_connection(validated_dbname)
        cursor = db.cursor()

        # Insert entities
        entity_path = os.path.join(working_dir, "all_entities.json")
        if not os.path.exists(entity_path):
            logger.warning(f"Entity file not found: {entity_path}")
        else:
            logger.info("Inserting entities...")
            with open(entity_path, "r") as f:
                val = []
                for level, entitys in enumerate(f):
                    local_entity = json.loads(entitys)
                    if type(local_entity) is not dict:
                        for entity in json.loads(entitys):
                            entity_name = entity['entity_name']
                            description = entity['description']
                            source_id = "|".join(entity['source_id'].split("|")[:5])
                            degree = entity['degree']
                            parent = entity['parent']
                            val.append((entity_name, description, source_id, degree, parent, level))
                    else:
                        entity = local_entity
                        entity_name = entity['entity_name']
                        description = entity['description']
                        source_id = "|".join(entity['source_id'].split("|")[:5])
                        degree = entity['degree']
                        parent = entity['parent']
                        val.append((entity_name, description, source_id, degree, parent, level))
                        
            if val:
                sql = "INSERT INTO entities(entity_name, description, source_id, degree, parent, level) VALUES (%s,%s,%s,%s,%s,%s)"
                try:
                    cursor.executemany(sql, tuple(val))
                    db.commit()
                    logger.info(f"Inserted {len(val)} entities")
                except Exception as e:
                    db.rollback()
                    logger.error(f"Error inserting entities: {e}")
                    raise

        # Insert relations
        relation_path = os.path.join(working_dir, "generate_relations.json")
        if not os.path.exists(relation_path):
            logger.warning(f"Relations file not found: {relation_path}")
        else:
            logger.info("Inserting relations...")
            with open(relation_path, "r") as f:
                val = []
                for relation_l in f:
                    relation = json.loads(relation_l)
                    src_tgt = relation['src_tgt']
                    tgt_src = relation['tgt_src']
                    description = relation['description']
                    weight = relation['weight']
                    level = relation['level']
                    val.append((src_tgt, tgt_src, description, weight, level))
                    
            if val:
                sql = "INSERT INTO relations(src_tgt, tgt_src, description, weight, level) VALUES (%s,%s,%s,%s,%s)"
                try:
                    cursor.executemany(sql, tuple(val))
                    db.commit()
                    logger.info(f"Inserted {len(val)} relations")
                except Exception as e:
                    db.rollback()
                    logger.error(f"Error inserting relations: {e}")
                    raise

        # Insert communities
        community_path = os.path.join(working_dir, "community.json")
        if not os.path.exists(community_path):
            logger.warning(f"Community file not found: {community_path}")
        else:
            logger.info("Inserting communities...")
            with open(community_path, "r") as f:
                val = []
                for community_l in f:
                    community = json.loads(community_l)
                    entity_name = community['entity_name']
                    entity_description = community['entity_description']
                    findings = str(community['findings'])
                    val.append((entity_name, entity_description, findings))
                    
            if val:
                sql = "INSERT INTO communities(entity_name, entity_description, findings) VALUES (%s,%s,%s)"
                try:
                    cursor.executemany(sql, tuple(val))
                    db.commit()
                    logger.info(f"Inserted {len(val)} communities")
                except Exception as e:
                    db.rollback()
                    logger.error(f"Error inserting communities: {e}")
                    raise

        cursor.close()
        db.close()
        logger.info("Successfully inserted all data to MySQL")
        
    except Exception as e:
        logger.error(f"Error in insert_data_to_mysql: {e}")
        raise


def find_tree_root(working_dir, entity):
    db = pymysql.connect(host='localhost', port=4321, user='root',
                         passwd='123',  charset='utf8mb4')
    dbname = os.path.basename(working_dir)
    res = [entity]
    cursor = db.cursor()
    db_name = os.path.basename(working_dir)
    depth_sql = f"select max(level) from {db_name}.entities"
    cursor.execute(depth_sql)
    depth = cursor.fetchall()[0][0]
    i = 0

    while i < depth:
        sql = f"select parent from {db_name}.entities where entity_name=%s "

        cursor.execute(sql, (entity))
        ret = cursor.fetchall()
        # print(ret)
        i += 1
        if len(ret) == 0:
            break
        entity = ret[0][0]
        res.append(entity)
    # res=list(set(res))
    # res = list(dict.fromkeys(res))

    return res


def find_path(entity1, entity2, working_dir, level, depth=5):
    db = pymysql.connect(host='localhost', port=4321, user='root',
                         passwd='123',  charset='utf8mb4')
    db_name = os.path.basename(working_dir)
    cursor = db.cursor()

    query = f"""
        WITH RECURSIVE path_cte AS (
            SELECT 
                src_tgt,
                tgt_src,
                 CAST(CONCAT(src_tgt, '|', tgt_src) AS CHAR(5000)) AS path,
                1 AS depth
            FROM {db_name}.relations
            WHERE src_tgt = %s
              AND level = %s

            UNION ALL

            SELECT 
                p.src_tgt,
                t.tgt_src,
                CONCAT(p.path, '|', t.tgt_src),
                p.depth + 1
            FROM path_cte p
            JOIN {db_name}.relations t ON p.tgt_src = t.src_tgt
            WHERE NOT FIND_IN_SET(
                  CONVERT(t.tgt_src USING utf8mb4) COLLATE utf8mb4_unicode_ci,
                  CONVERT(p.path USING utf8mb4) COLLATE utf8mb4_unicode_ci
              )
              AND level = %s
              AND p.depth < %s
        )
        SELECT path
        FROM path_cte
        WHERE tgt_src = %s
        ORDER BY depth ASC
        LIMIT 1;
    """
    cursor.execute(query, (entity1, level, level, depth, entity2))
    result = cursor.fetchone()

    if result:
        return result[0].split('|')  # 返回节点列表
    else:
        return None


def search_nodes_link(entity1, entity2, working_dir, level=0):
    # cursor = db.cursor()
    # db_name=os.path.basename(working_dir)
    # sql=f"select * from {db_name}.relations where src_tgt=%s and tgt_src=%s and level=%s"
    # cursor.execute(sql,(entity1,entity2,level))
    # ret=cursor.fetchall()
    # if len(ret)==0:
    #     sql=f"select * from {db_name}.relations where src_tgt=%s and tgt_src=%s and level=%s"
    #     cursor.execute(sql,(entity2,entity1,level))
    #     ret=cursor.fetchall()
    # if len(ret)==0:
    #     return None
    # else:
    #     return ret[0]
    db = pymysql.connect(host='localhost', port=4321, user='root',
                         passwd='123',  charset='utf8mb4')
    cursor = db.cursor()
    db_name = os.path.basename(working_dir)
    sql = f"select * from {db_name}.relations where src_tgt=%s and tgt_src=%s "
    cursor.execute(sql, (entity1, entity2))
    ret = cursor.fetchall()
    if len(ret) == 0:
        sql = f"select * from {db_name}.relations where src_tgt=%s and tgt_src=%s "
        cursor.execute(sql, (entity2, entity1))
        ret = cursor.fetchall()
    if len(ret) == 0:
        return None
    else:
        return ret[0]


def search_chunks(working_dir, entity_set):
    db = pymysql.connect(host='localhost', port=4321, user='root',
                         passwd='123',  charset='utf8mb4')
    res = []
    db_name = os.path.basename(working_dir)
    cursor = db.cursor()
    for entity in entity_set:
        if entity == 'root':
            continue
        sql = f"select source_id from {db_name}.entities where entity_name=%s "
        cursor.execute(sql, (entity,))
        ret = cursor.fetchall()
        res.append(ret[0])
    return res


def search_nodes(entity_set, working_dir):
    db = pymysql.connect(host='localhost', port=4321, user='root',
                         passwd='123',  charset='utf8mb4')
    res = []
    db_name = os.path.basename(working_dir)
    cursor = db.cursor()
    for entity in entity_set:
        sql = f"select * from {db_name}.entities where entity_name=%s and level=0"
        cursor.execute(sql, (entity,))
        ret = cursor.fetchall()
        res.append(ret[0])
    return res


def get_text_units(working_dir, chunks_set, chunks_file, k=5):
    db_name = os.path.basename(working_dir)
    chunks_list = []
    for chunks in chunks_set:
        if "|" in chunks:
            temp_chunks = chunks.split("|")
        else:
            temp_chunks = [chunks]
        chunks_list += temp_chunks
    counter = Counter(chunks_list)

    # 筛选出出现多次的元素
    # duplicates = [item for item, count in counter.items() if count > 2]
    duplicates = [item for item, _ in sorted(
        [(item, count) for item, count in counter.items() if count > 1],
        key=lambda x: x[1],
        reverse=True
    )[:k]]
    if len(duplicates) < k:
        used = set(duplicates)
        for item, _ in counter.items():
            if item not in used:
                duplicates.append(item)
                used.add(item)
            if len(duplicates) == k:
                break

    chunks_dict = {}
    text_units = ""
    with open(chunks_file, 'r')as f:
        if chunks_file.endswith('.jsonl'):
            # Handle JSONL format (one JSON object per line)
            chunks_data = []
            for line in f:
                chunks_data.append(json.loads(line.strip()))
        else:
            # Handle JSON format (single JSON array)
            chunks_data = json.load(f)
    chunks_dict = {item["hash_code"]: item["text"] for item in chunks_data}

    for chunks in duplicates:
        text_units += chunks_dict[chunks]+"\n"
    return text_units


def search_community(entity_name, working_dir):
    """
    Search for community information with improved error handling.
    """
    try:
        # Handle case where working_dir ends with slash
        clean_path = working_dir.rstrip('/')
        dbname = os.path.basename(clean_path)
        validated_dbname = validate_database_name(dbname)
        
        db = get_mysql_connection(validated_dbname)
        cursor = db.cursor()
        sql = "SELECT * FROM communities WHERE entity_name=%s"
        cursor.execute(sql, (entity_name,))
        ret = cursor.fetchall()
        cursor.close()
        db.close()
        
        if len(ret) != 0:
            return ret[0]
        else:
            return ""
            
    except Exception as e:
        logger.error(f"Error searching community for entity {entity_name}: {e}")
        return ""


def insert_origin_relations(working_dir):
    """
    Insert origin relations with improved error handling and logging.
    """
    logger.info(f"Inserting origin relations for working directory: {working_dir}")
    
    clean_path = working_dir.rstrip('/')
    dbname = os.path.basename(clean_path)
    validated_dbname = validate_database_name(dbname)
    
    try:
        db = get_mysql_connection(validated_dbname)
        cursor = db.cursor()
        
        # relation_path=os.path.join(f"datasets/{dbname}","relation.jsonl")
        # relation_path=os.path.join(f"/data/zyz/reproduce/HiRAG/eval/datasets/{dbname}/test")
        relation_path = os.path.join(f"hi_ex/{dbname}", "relation.jsonl")
        # relation_path=os.path.join(f"32b/{dbname}","relation.jsonl")
        
        if not os.path.exists(relation_path):
            logger.warning(f"Origin relations file not found: {relation_path}")
            return
            
        logger.info("Inserting origin relations...")
        with open(relation_path, "r") as f:
            val = []
            skipped_count = 0
            for relation_l in f:
                relation = json.loads(relation_l)
                src_tgt = relation['src_tgt']
                tgt_src = relation['tgt_src']
                if len(src_tgt) > 190 or len(tgt_src) > 190:
                    logger.warning(f"Skipping relation with long text: {src_tgt[:50]}... -> {tgt_src[:50]}...")
                    skipped_count += 1
                    continue
                description = relation['description']
                weight = relation['weight']
                level = 0
                val.append((src_tgt, tgt_src, description, weight, level))
                
        if val:
            sql = "INSERT INTO relations(src_tgt, tgt_src, description, weight, level) VALUES (%s,%s,%s,%s,%s)"
            try:
                cursor.executemany(sql, tuple(val))
                db.commit()
                logger.info(f"Inserted {len(val)} origin relations (skipped {skipped_count})")
            except Exception as e:
                db.rollback()
                logger.error(f"Error inserting origin relations: {e}")
                raise
        else:
            logger.warning("No valid origin relations to insert")
            
        cursor.close()
        db.close()
        
    except Exception as e:
        logger.error(f"Error in insert_origin_relations: {e}")
        raise


if __name__ == "__main__":
    working_dir = 'exp/compare_hirag_opt1_commonkg_32b/mix'
    # build_vector_search()
    # search_vector_search()
    create_db_table_mysql(working_dir)
    insert_data_to_mysql(working_dir)
    insert_origin_relations(working_dir)
    # print(find_tree_root(working_dir,'Policies'))
    # print(search_nodes_link('Innovation Policy Network','document',working_dir,0))
    # from query_graph import embedding
    # topk=200
    # query=embedding("mary")
    # milvus_client = MilvusClient(uri=f"/cpfs04/user/zhangyaoze/workspace/trag/ttt/milvus_demo.db")
    # collection_name = "entity_collection"
    # # query_embedding = emb_text(query)
    # search_results = milvus_client.search(
    #     collection_name=collection_name,
    #     data=query,
    #     limit=topk,
    #     filter=' level ==1 ',
    #     params={"metric_type": "L2", "params": {}},
    #     output_fields=["entity_name", "description","vector","level"],
    # )
    # print(len(search_results[0]))
    # for entity in search_results[0]:
    #     if entity['entity']['level']!=1:
    #         print(entity)

    # search_results2 = milvus_client.search(
    #     collection_name=collection_name,
    #     data=[vec],
    #     limit=topk,
    #     params={"metric_type": "L2", "params": {}},
    #     output_fields=["entity_name", "description","vector"],
    # )
    # recall=search_results2[0][0]['entity']['vector']
    # print(recall==vec)
