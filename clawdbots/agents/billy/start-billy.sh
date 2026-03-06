#!/bin/bash
# Start Billy in Docker (isolated from Anton)

cd "$(dirname "$0")"

echo "🦞 Starting Billy Bot in Docker..."
echo ""
echo "Billy will run on port 18790 (isolated from Anton on port 18789)"
echo ""

# Build if needed
if ! docker images | grep -q "billy-bot"; then
    echo "Building Billy Docker image..."
    docker-compose build
fi

# Start
echo "Starting Billy container..."
docker-compose up -d

# Show status
echo ""
echo "Waiting for Billy to start..."
sleep 5

docker-compose logs --tail=20

echo ""
echo "✅ Billy running!"
echo ""
echo "Check status: docker-compose logs -f"
echo "Stop Billy: docker-compose down"
echo "Restart Billy: docker-compose restart"
