#!/bin/bash
export SECRET=secret
/opt/keycloak/bin/kc.sh bootstrap-admin service --client-id test --client-secret:env=SECRET
exec /opt/keycloak/bin/kc.sh start-dev --log=console --log-console-level=debug --http-enabled true
