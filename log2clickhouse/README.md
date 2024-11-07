# Log Reader for ClickHouse Integration

This script provides an efficient log reader that tailors log files, processes the data, and inserts it into ClickHouse. The script reads logs line-by-line, handles position tracking, and supports customizable logging and ClickHouse configuration via a YAML configuration file.

## Features
- **Efficient file reading**: The log reader reads large log files efficiently, only processing new lines as they are added.
- **Position tracking**: Keeps track of the last read position in each file to avoid reprocessing logs.
- **Flexible configuration**: All settings can be controlled via a YAML file, including logging settings, log patterns, and ClickHouse settings.
- **ClickHouse Integration**: Insert logs into ClickHouse with customizable tables and columns.
- **Logging control**: Enable/disable logging and control logging levels via the configuration file.

## Installation

1. Clone the repository:
```bash
   git clone https://github.com/pjuwyD/tools.git
```

2. Install the required dependencies:

```bash
   # Inside directory tools/log2clickhouse
   pip install -r requirements.txt
```

This script requires the following Python packages:

- `glob` (Standard library)
- `json` (Standard library)
- `os` (Standard library)
- `time` (Standard library)
- `logging` (Standard library)
- `yaml`
- `argparse` (Standard library)
- `watchdog`
- `clickhouse-driver`

## Usage

## Running the log2clickhouse
To run the log2clickhouse, use the following command:
```bash 
    python log2clickhouse.py -c /path/to/your/config.yml
```

## Configuration File (YAML)
The configuration file allows you to specify various settings for the log reader. Below is an example configuration file.

### Example Configuration (config.yml)
```yaml
    # Logging configuration
    logging:
      enabled: true  # Set to false to disable logging
      level: info    # Log level (info, debug, warning, error, critical)

    # Log Reader configuration
    log_reader:
      batch_size: 100  # Number of records to batch before inserting into ClickHouse
      watched_patterns:
        - "/var/log/*.log"  # Log file patterns to watch
      position_file:
        path: "log_reader_positions.json"  # Path to position file, default is 'log_reader_positions.json'

    # ClickHouse configuration
    clickhouse:
      host: "127.0.0.1"       # ClickHouse server hostname
      port: 9000              # ClickHouse server port
      database: "default"     # ClickHouse database
      table: "logs_table"     # ClickHouse table name (must be provided)
    
    # Table columns configuration
      table_columns:
        - name: "logdatetime"
          type: "DateTime"
        - name: "message"
          type: "String"
          mask: "event"
        - name: "pid"
          type: "UInt32"
        - name: "thread"
          type: "Float64"
      arbitrary_data:
        enabled: true
        column: "arbitrary"
```

### Configuration Breakdown:
#### logging:
- **enabled**: Whether logging is enabled (default is true).
- **level**: Logging level (options: `info`, `debug`, `warning`, `error`, `critical`).

#### log_reader:
- **batch_size**: Number of records to batch together before inserting into ClickHouse.
- **watched_patterns**: List of file patterns to monitor for new logs (supports wildcards like `*.log`).
- **position_file.path**: Path to the position file where the reading position is stored. Default is `log_reader_positions.json`.

#### clickhouse:
- **host**: ClickHouse server hostname (default is `127.0.0.1`).
- **port**: ClickHouse server port (default is `9000`).
- **database**: ClickHouse database name (default is `default`).
- **table**: ClickHouse table name (this is mandatory and should be defined in the configuration).

#### table_columns:
Defines the columns in the ClickHouse table.
- **name**: Column name in the table.
- **type**: Data type of the column (e.g., `String`, `DateTime`, `UInt32`).
- **mask**: Entry name in the log

#### arbitrary_data
Defines should the arbitrary data be stored and where should it be stored
- **enabled**: Should arbitrary data be stored (default is `false`)
- **arbitrary_column**: Where should arbitrary data be stored (default is `arbitrary`)

