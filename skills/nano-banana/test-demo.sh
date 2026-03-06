#!/bin/bash
# Demo script for nano-banana (requires GEMINI_API_KEY)

echo "=== Nano-Banana Test Demo ==="
echo ""

# Check if API key is configured
if [[ "$GEMINI_API_KEY" == "YOUR_GEMINI_API_KEY_HERE" ]] || [[ -z "$GEMINI_API_KEY" ]]; then
    echo "⚠️  GEMINI_API_KEY not configured"
    echo ""
    echo "To test nano-banana:"
    echo "1. Get API key from https://aistudio.google.com/apikey"
    echo "2. Edit /root/.openclaw/workspace/config/mcporter.json"
    echo "3. Replace YOUR_GEMINI_API_KEY_HERE with your actual key"
    echo "4. Run: mcporter list"
    echo ""
    echo "Then try:"
    echo ""
    echo "  mcporter call nano-banana generate_image --params '{"
    echo "    \"prompt\": \"a cute cat wearing sunglasses on a beach\","
    echo "    \"aspectRatio\": \"1:1\","
    echo "    \"outputPath\": \"./test-cat.png\""
    echo "  }'"
    echo ""
    exit 1
fi

echo "✓ API key configured"
echo ""

# Test 1: Simple generation
echo "Test 1: Generating test image..."
mcporter call nano-banana generate_image --params '{
  "prompt": "a simple test image showing a sunset over mountains, digital art style",
  "aspectRatio": "16:9",
  "outputPath": "./test-output.png"
}'

if [[ -f "./test-output.png" ]]; then
    echo "✓ Image generated: test-output.png"
    ls -lh test-output.png
else
    echo "✗ Image generation failed"
fi

echo ""
echo "=== Demo Complete ==="
