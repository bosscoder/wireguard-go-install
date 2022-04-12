There are two different binaries provided.

Standard version is built with default values.
Lite version is built for systems with limited RAM (ex. 256MB or lower):
`MaxSegmentSize             = 1700`
`PreallocatedBuffersPerPool = 1024`
This will make it use a fixed amount of RAM (~20 MB max), rather than allowing memory usage to grow infinitely.