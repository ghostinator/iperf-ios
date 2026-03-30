# iPerf iOS (UDP Enhanced)

Run a modern [iPerf3](https://iperf.fr/) client on your iPhone or iPad. This fork extends the original project by adding support for UDP testing, alongside standard TCP, reverse mode, and multiple stream selection.

<img width="429" height="924" alt="image" src="https://github.com/user-attachments/assets/2c1b24b9-fb85-425e-9eee-71abde22049d" align="center" />

## Features

*   **UDP Support**: Test bandwidth, jitter, and packet loss using UDP.
    
*   **Modern iPerf 3**: Based on a reliable iPerf 3.x codebase for accurate results.
    
*   **Lightweight**: Minimalist footprint and resource usage.
    
*   **High Performance**: Bandwidth tests run in high-priority background threads to ensure the UI doesn't bottleneck the throughput.
    
*   **Simple UI**: Focused on getting straight to the iPerf parameters you need.
    
*   **Open Source**: Licensed for the community to use, study, and improve.
    

## Why use this version?

While there are several iPerf apps available, many are outdated, prone to crashing, or lack granular control over protocol types. This version aims to be:

*   **Stable**: Focused on a crash-free experience during high-throughput tests.
    
*   **Fast**: Optimized system calls and memory management.
    
*   **Current**: Includes the UDP options previously missing from the upstream mobile client.
    

## Building and Contributing

To build the app, clone the repository and open the project in Xcode.

### Local Development

1.  Clone the repo: `git clone https://github.com/ghostinator/iperf-ios.git`
    
2.  Open `iperf-ios.xcodeproj` in Xcode.
    
3.  Ensure you have a valid development team selected to deploy to a physical device.
    

Pull requests and issues are welcome. If you find a bug or have a feature request for the UDP implementation, please open an issue in this repository.

## Future Roadmap

*   \[ \] Graphs and real-time progress visualization.
    
*   \[ \] Indefinite test duration (test until manually stopped).
    
*   \[ \] LAN scanning for active iPerf servers.
    
*   \[ \] Latency and Jitter-specific reporting improvements.
    
*   \[ \] Localized UI support.
