#!/bin/bash
mosquitto_pub -h 192.168.32.9 -u ywyh -P 'ywyh@204' -t b0a604429004-set -m '{"key":0,"messageId":"","type":"event"}'
sleep 5
mosquitto_pub -h 192.168.32.9 -u ywyh -P 'ywyh@204' -t b0a604429004-set -m '{"key":1,"messageId":"","type":"event"}'
