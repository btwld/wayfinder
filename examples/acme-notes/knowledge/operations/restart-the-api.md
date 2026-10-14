---
type: Runbook
title: Restart the API
description: How to restart the API service without dropping requests.
---

# Restart the API

1. Drain the API instances from the load balancer.
2. Restart the service on each instance.
3. Return the instances to the load balancer once health checks pass.
