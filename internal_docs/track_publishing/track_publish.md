# Track publishing

Tracks published in RTC Engine can have multiple formats like: `:raw` or `:RTP`. When you publish track with multiple formats, we assume that packets will come in format different that `:raw` and that `depayloading_filter` element will transform packets to `:raw` format. RTC Engine will have two tees to distribute packets in different formats. First tee will be responsible for distributing non `:raw` packets and it is spawned after receiving `:track_ready` notification. Second tee with name `:raw_format_tee`, which is responsible for distributing track in raw format is spawned at the moment, when somebody subscribe on track in `:raw` format. At this moment also `depayloading_filter` will be spawned. 

When you publish track with only `:raw` format RTC Engine will spawn only `:raw_format_tee`.

Case with multiple format is shown in the upper part of the diagram below.
Case with track only in raw format is show in the lower part of diagram below.


## Engine Architecture

![Alt text](assets/tee_diagram.drawio.svg)