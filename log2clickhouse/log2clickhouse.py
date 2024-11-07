import glob
import json
import os
import time
import logging
import yaml
import argparse
from datetime import datetime
from typing import Dict, Any, Union
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from clickhouse_driver import Client

# Load configuration from YAML
def load_config(config_file):
    with open(config_file, 'r') as f:
        return yaml.safe_load(f)

# Configure logging based on the configuration
def configure_logging(log_config):
    if log_config.get('enabled', True):  # Default enabled if not provided
        logging_level = log_config.get('level', 'info').upper()  # Default level 'info'
        logging.basicConfig(level=getattr(logging, logging_level), format="%(asctime)s - %(levelname)s - %(message)s")
    else:
        logging.basicConfig(level=logging.CRITICAL)  # Disable all logs if 'enabled' is False

# Configure logging
logger = logging.getLogger()

# Load and save file positions
def load_positions(position_file):
    if os.path.exists(position_file):
        with open(position_file, 'r') as f:
            return json.load(f)
    return {}

def save_positions(positions, position_file):
    with open(position_file, 'w') as f:
        json.dump(positions, f)

class LogHandler(FileSystemEventHandler):
    def __init__(self, client, table, batch_size, watched_patterns, position_file, table_columns, store_arbitrary, arbitrary_column):
        self.client = client
        self.table = table
        self.batch_size = batch_size
        self.watched_patterns = watched_patterns
        self.position_file = position_file
        self.positions = load_positions(position_file)
        self.table_columns = table_columns
        self.store_arbitrary = store_arbitrary
        self.arbitrary_column = arbitrary_column
        self.batch = []
        logger.debug("LogHandler initialized with batch size %d", batch_size)

    def process_log_line(self, filepath, line):
        logger.debug("Processing line from file %s", filepath)
        try:
            log_entry = json.loads(line)
            processed_log = self.process_log(log_entry)
            self.batch.append(processed_log)
            logger.debug("Added log entry to batch: %s", processed_log)
            if len(self.batch) >= self.batch_size:
                logger.debug("Batch size reached. Inserting %d records into ClickHouse.", len(self.batch))
                self.client.execute(
                    f"INSERT INTO {self.table} VALUES",
                    self.batch
                )
                logger.info("Inserted batch of %d records into ClickHouse.", len(self.batch))
                self.batch = []
        except json.JSONDecodeError:
            logger.warning("Skipping malformed JSON log in file %s: %s", filepath, line.strip())

    def process_log(self, log: Dict[str, Any]) -> Dict[str, Union[str, int, float, None]]:
        processed = {}
        used_keys = set()  # Track keys that are processed

        for column in self.table_columns:
            column_name = column['name']
            column_type = column.get('type', 'String')  # Default type is 'String'
            column_mask = column.get('mask', '')  # Mask option

            # Use the mask if specified, otherwise default to column name
            actual_key = column_mask or column_name
            value = log.get(actual_key, None)
            used_keys.add(actual_key)  # Mark this key as used

            if value is None:
                # Apply default values based on type if necessary
                if column_type == 'String':
                    processed[column_name] = ""
                elif column_type in ['UInt32', 'Int32', 'Float32', 'Float64']:
                    processed[column_name] = None
                elif column_type == 'DateTime':
                    processed[column_name] = datetime.now()
            else:
                # Apply type conversions based on column type
                if column_type == 'UInt32':
                    try:
                        processed[column_name] = int(value)
                        if processed[column_name] < 0:
                            processed[column_name] = None  # Ensure non-negative
                    except (ValueError, TypeError):
                        processed[column_name] = None
                elif column_type == 'Int32':
                    try:
                        processed[column_name] = int(value)
                    except (ValueError, TypeError):
                        processed[column_name] = None
                elif column_type in ['Float32', 'Float64']:
                    try:
                        processed[column_name] = float(value)
                    except (ValueError, TypeError):
                        processed[column_name] = None
                elif column_type == 'DateTime':
                    try:
                        processed[column_name] = datetime.fromisoformat(value)
                    except (ValueError, TypeError):
                        processed[column_name] = datetime.now()  # Fallback to current datetime
                else:
                    processed[column_name] = str(value)  # Default to string if unknown type

        # Handle arbitrary data - any key-value pairs not matching the table columns
        if self.store_arbitrary:
            arbitrary_data = {k: v for k, v in log.items() if k not in used_keys}
            processed[self.arbitrary_column] = json.dumps(arbitrary_data)

        return processed

    def on_modified(self, event):
        if event.is_directory:
            return
        filepath = event.src_path
        last_pos = self.positions.get(filepath, 0)
        
        logger.debug("File modified: %s. Reading from last position: %d", filepath, last_pos)
        with open(filepath, 'r') as f:
            f.seek(last_pos)
            for line in f:
                self.process_log_line(filepath, line)
            self.positions[filepath] = f.tell()
            save_positions(self.positions, self.position_file)
            logger.debug("Updated position for %s to %d", filepath, self.positions[filepath])

    def on_created(self, event):
        if event.is_directory:
            return
        logger.debug("File created: %s", event.src_path)
        self.on_modified(event)

def main(config):
    client = Client(
        host=config.get('clickhouse', {}).get('host', '127.0.0.1'), 
        port=config.get('clickhouse', {}).get('port', 9000),
        database=config.get('clickhouse', {}).get('database', 'default')
    )
    
    # Ensure the table and columns are mandatory
    if 'table' not in config.get('clickhouse', {}):
        logger.error("ClickHouse table is mandatory but not provided in the configuration.")
        exit(1)
    if 'table_columns' not in config.get('clickhouse', {}):
        logger.error("ClickHouse table columns are mandatory but not provided in the configuration.")
        exit(1)
    
    # Read table columns with name, type, and optional mask from config
    table_columns = config['clickhouse'].get('table_columns', [])
    store_arbitrary = config['clickhouse'].get('arbitrary_data', {}).get("enabled", False)
    arbitrary_column = config['clickhouse'].get('arbitrary_data', {}).get("column", "arbitrary")
    position_file = config.get('position_file', {}).get('path', 'log_reader_positions.json')
    event_handler = LogHandler(client, config['clickhouse']['table'], 
                                config['log_reader'].get('batch_size', 100), 
                                config['log_reader']['watched_patterns'], 
                                position_file, 
                                table_columns, store_arbitrary, arbitrary_column)
    
    observer = Observer()

    # Expand each pattern and add each matching file to the observer
    for pattern in config['log_reader']['watched_patterns']:
        logger.debug("Expanding pattern: %s", pattern)
        for filepath in glob.glob(pattern):
            logger.info("Adding file to watch: %s", filepath)
            observer.schedule(event_handler, filepath, recursive=False)

    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
    logger.info("Log reader terminated.")

if __name__ == '__main__':
    # Argument parsing for the configuration file
    parser = argparse.ArgumentParser(description="Efficient Log Reader for Large Files with ClickHouse Integration")
    parser.add_argument('-c', '--config', required=True, help="Path to the YAML configuration file")
    args = parser.parse_args()

    # Load the configuration
    config = load_config(args.config)

    # Configure logging
    configure_logging(config.get('logging', {}))
    
    logger.info("Starting log reader with ClickHouse target %s:%d/%s, table %s", 
                 config['clickhouse'].get('host', '127.0.0.1'), 
                 config['clickhouse'].get('port', 9000), 
                 config['clickhouse'].get('database', 'default'), 
                 config['clickhouse']['table'])
    
    main(config)
