#!/bin/bash
docker run -d \
  --name='chromium' \
  -e PUID=5001 \
  -e PGID=5001 \
  -e TZ=Etc/UTC \
  --shm-size="1gb" \
  -p 9009:3000 chromium