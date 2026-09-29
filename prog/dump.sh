#!/bin/bash
hexdump -e '"1%03_ax: " 16/1 "%02X " "\n"' $1 | awk '{print toupper($0)}'
