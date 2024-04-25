# Virtual Timur

Virtual Timur is a script that sets up a container environment using Linux namespaces and loop devices. It helps in creating and managing container filesystems and running container instances.

## How to Run

To run the Virtual Timur script, follow these steps:

1. Make sure you have root privileges to execute the script:

   ```bash
   sudo ./timur.sh
   ```

2. The script will check if you are running as root, set up paths for images and mount points, and initialize the Virtual Timur environment.

3. Follow the interactive prompts to create and manage container instances using the provided options.


## Usage

The timur.sh script can be used to:
- Create container filesystems
- Mount container filesystems
- Run and manage container instances
- Benchmark container performance against the host system
For detailed usage instructions, run the script with the -h or --help option:


# Uncompleted

## Virtual Timur

Virtual Timur is a container-based virtualization system that allows users to create and run containers on a Linux system. It uses low-level Linux features such as namespaces, cgroups, and the `unshare` command to provide isolation and security for containers.

### Prerequisites

Before running Virtual Timur, you need to have the following installed on your system:

- Ubuntu 20.04 or a later version
- Docker (for building the root filesystem image)

### Installation

To install Virtual Timur, follow these steps:

1. Clone this repository to your local machine:

   ```bash
   git clone https://github.com/your-username/virtual_timur.git
   ```

2. See possible ways how to use it

    ```text
    Usage: virtual_timur.bash [OPTION] [CONTAINER_NAME]
    Options:
        -h, --help    Show this help message
        init          Initialize virtual timur
        build         Build a new container
        run           Run a container
        list, ls      List all containers
        stop          Stop a container
        rm, remove    Remove a container
        clear         Clear all containers
    ```

