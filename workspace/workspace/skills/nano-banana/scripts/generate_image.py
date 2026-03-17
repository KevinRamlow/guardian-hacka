#!/usr/bin/env python3
"""
Wrapper script for Gemini image generation with proper file saving support.
Usage: generate_image.py --prompt "..." [--output path.png] [--aspect-ratio 1:1] [--model ...]
"""
import os
import sys
import json
import argparse
import base64
import requests

# Default API key from env or config
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    print(json.dumps({"success": False, "error": "GEMINI_API_KEY not set. Source $OPENCLAW_HOME/.env first."}), file=sys.stderr)
    sys.exit(1)

# Model mappings
MODEL_MAP = {
    "gemini-3-pro-image-preview": "gemini-3-pro-image-preview",
    "gemini-2.5-flash-preview-05-20": "gemini-2.5-flash-image",  # Map old name to new
    "gemini-2.5-flash-image": "gemini-2.5-flash-image",
    "gemini-2.0-flash-exp": "gemini-2.5-flash-image",  # Fallback
    "default": "gemini-2.5-flash-image"
}

def generate_image(prompt, output_path=None, aspect_ratio="1:1", model="default"):
    """Generate an image using Gemini API and optionally save to disk."""
    
    # Map model name
    api_model = MODEL_MAP.get(model, MODEL_MAP["default"])
    
    # Construct API URL
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{api_model}:generateContent?key={API_KEY}"
    
    # Build payload
    payload = {
        "contents": [{
            "parts": [{
                "text": prompt
            }]
        }],
        "generationConfig": {
            "responseModalities": ["image"]
        }
    }
    
    # Add aspect ratio if supported (note: this might not work for all models)
    if aspect_ratio and aspect_ratio != "1:1":
        # Gemini might not support aspect ratio in the API, but we'll try
        pass
    
    try:
        response = requests.post(url, json=payload, timeout=60)
        
        if response.status_code != 200:
            error_msg = f"API error {response.status_code}: {response.text[:500]}"
            print(json.dumps({"success": False, "error": error_msg}), file=sys.stderr)
            return None
        
        data = response.json()
        
        # Extract image data
        image_data = None
        mime_type = None
        
        if "candidates" in data:
            for candidate in data["candidates"]:
                if "content" in candidate:
                    for part in candidate["content"].get("parts", []):
                        if "inlineData" in part:
                            mime_type = part["inlineData"].get("mimeType", "image/png")
                            image_data = part["inlineData"].get("data")
                            break
                if image_data:
                    break
        
        if not image_data:
            print(json.dumps({"success": False, "error": "No image data in API response"}), file=sys.stderr)
            return None
        
        # Decode base64
        try:
            image_bytes = base64.b64decode(image_data)
        except Exception as e:
            print(json.dumps({"success": False, "error": f"Failed to decode base64: {str(e)}"}), file=sys.stderr)
            return None
        
        # Save to file if output_path provided
        if output_path:
            try:
                # Create parent directory if it doesn't exist
                os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else ".", exist_ok=True)
                
                with open(output_path, "wb") as f:
                    f.write(image_bytes)
                
                result = {
                    "success": True,
                    "output_path": os.path.abspath(output_path),
                    "size_bytes": len(image_bytes),
                    "mime_type": mime_type,
                    "model": api_model
                }
                print(json.dumps(result))
                return output_path
                
            except Exception as e:
                print(json.dumps({"success": False, "error": f"Failed to save file: {str(e)}"}), file=sys.stderr)
                return None
        else:
            # Return base64 data if no output path
            result = {
                "success": True,
                "base64_data": image_data[:100] + "...",  # Truncate for display
                "size_bytes": len(image_bytes),
                "mime_type": mime_type,
                "model": api_model,
                "note": "Image generated but not saved (no output_path provided)"
            }
            print(json.dumps(result))
            return image_data
            
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Unexpected error: {str(e)}"}), file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(description="Generate images using Gemini API")
    parser.add_argument("--prompt", required=True, help="Image generation prompt")
    parser.add_argument("--output", "-o", help="Output file path (e.g., ./image.png)")
    parser.add_argument("--aspect-ratio", default="1:1", help="Aspect ratio (1:1, 16:9, etc.)")
    parser.add_argument("--model", default="default", help="Gemini model to use")
    
    args = parser.parse_args()
    
    result = generate_image(
        prompt=args.prompt,
        output_path=args.output,
        aspect_ratio=args.aspect_ratio,
        model=args.model
    )
    
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
