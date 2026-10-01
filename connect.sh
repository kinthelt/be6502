#!/bin/bash
picocom -b 115200 -f h --receive-cmd "rx -c -b -X -vv" --send-cmd "sx -vv" $1
