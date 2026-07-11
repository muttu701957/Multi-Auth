#!/bin/sh
set -e

npx prisma migrate deploy

npm run seed:clients

npm run start
