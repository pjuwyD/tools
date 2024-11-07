# Network Distortion Tool

This project provides two tools for manipulating network parameters like latency and rate limiting on a specified network interface. The Python script supports both inbound and outbound traffic filtering by IP address, and allows configurable distortion durations. The Bash script provides a simpler command-line interface for introducing network delay and resetting network interfaces.

## Requirements

- Python 3.x
- Linux system with `tc` (traffic control) command available
- Sudo privileges to modify network interfaces and traffic control settings

## Installation

No installation is required. Just ensure that the scripts have execute permissions and that `tc` is available on your system.

```bash
chmod +x netdeg.py
chmod +x netdeg.sh
```
## Usage
### Python Script: `netdeg.py`

The Python script accepts several command-line arguments that define the network distortion parameters. It can also be used to reset the network to its original state.

#### Command-Line Arguments

| Argument       | Description | Default Value |
|----------------|-------------|---------------|
| `--interface`  | Network interface to apply distortion (e.g., eth0, wlan0) | `eth0` |
| `--ip`         | IP address to filter traffic for distortion. If not specified, all traffic is affected. | None |
| `--rate`       | Rate limit for traffic in kbps (kilobits per second). | `100` |
| `--latency`    | Latency (delay) in milliseconds to introduce on traffic. | `0` |
| `--traffic`    | Type of traffic to distort, can be either `inbound` or `outbound`. | `outbound` |
| `--duration`   | Duration of the distortion in seconds. | `60` |
| `--reset`      | If specified, the network distortion is reset instead of applied. | `False` |

#### Examples

1. **Distort network with latency and rate limit**:

```bash
   python3 netdeg.py --interface eth0 --traffic outbound --duration 10 --latency 500 --rate 100
```
This will introduce a 500ms latency and limit the rate to 100kbps for outgoing traffic on eth0 for 10 seconds.

2. **Distort network traffic to/from a specific IP**:

```bash
    python3 netdeg.py --interface eth0 --traffic inbound --duration 20 --latency 200 --ip 192.168.1.10
```
This will apply a 200ms latency on incoming traffic from the IP 192.168.1.10 for 20 seconds on eth0.

3. **Reset the network interface**:

```bash
    python3 netdeg.py --interface eth0 --traffic inbound --duration 20 --latency 200 --ip 192.168.1.10
```
This will reset any applied distortions on the eth0 network interface.

### Bash Script: `netdeg.sh`

The Bash script provides a simpler interface for adding network delay to a specified interface. It also allows for resetting the interface settings.

#### Usage

```bash
./netdeg.sh [-h] [-i d l] -- script to introduce network delay (in ms) to a specified link
```

#### Where:

| Option | Description |
|--------|-------------|
| `-h`    | Shows help and usage |
| `-r`    | Resets interface settings |
| `-i`    | Sets the interface (e.g., eth0) |
| `-d`    | Sets the destination IP address |
| `-l`    | Sets the delay in ms |

#### Example Usage

1. **Apply delay to a specific interface and IP**:

```bash
   ./netdeg.sh -i eth0 -d 10.34.4.102 -l 100ms
```
This will introduce a 100ms delay to traffic going to IP 10.34.4.102 on eth0.

2. **Reset the network interface settings**:
```bash
   ./netdeg.sh -r -i eth0
```
This will reset the network settings on eth0.

## How It Works

Both the Python and Bash scripts use the `tc` (traffic control) utility to manipulate network parameters:

- **Latency**: Introducing delay in network packets.
- **Rate Limiting**: Restricting the bandwidth of the network.
- **Traffic Filtering**: Only applying the impairments to inbound or outbound traffic for a specific IP address.

Once the distortion is applied, the scripts will wait for the specified duration and automatically remove the impairment.

## Resetting Network State

The scripts will automatically clean up network distortions after the specified duration. However, if the program was abruptly stopped, you can manually reset the network distortions using the `--reset` flag in Python or `-r` flag in Bash.

