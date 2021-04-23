#!/bin/bash
ansible all -m command -a "shutdown -h now"
