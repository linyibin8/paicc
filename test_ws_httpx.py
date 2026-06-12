#!/usr/bin/env python3
"""
PAI-CC WebSocket QA Flow Test using httpx
"""
import asyncio
import json
import base64

async def test_websocket():
    try:
        import httpx
    except ImportError:
        print("httpx not available, installing...")
        import subprocess
        subprocess.run(["pip", "install", "httpx", "websockets"], check=True)
        import httpx

    print("=" * 60)
    print("PAI-CC WebSocket QA Flow Test")
    print("=" * 60)
    print()

    results = {
        "connected": False,
        "thinking": False,
        "partial_count": 0,
        "answer_received": False,
        "tts_started": False,
        "tts_ready": False,
        "errors": []
    }

    # Create a simple HTTP request to upgrade to WebSocket
    import httpx

    async with httpx.AsyncClient(timeout=120.0) as client:
        # First, let's try the text-only REST API to verify Ollama works
        print("[0/5] Testing REST API (fallback verification)...")
        try:
            response = await client.post(
                "http://localhost:8030/api/v1/qa/ask/text-only",
                data={
                    "query": "1+1等于几？",
                    "session_id": "test_session_001",
                    "enable_tts": "false"
                }
            )
            if response.status_code == 200:
                data = response.json()
                print(f"  [OK] REST API works: {data.get('answer', '')[:100]}...")
            else:
                print(f"  [FAIL] REST API returned {response.status_code}")
        except Exception as e:
            print(f"  [ERROR] REST API failed: {e}")
        print()

        # Now test WebSocket
        print("[1/5] Testing WebSocket connection...")

        # Use httpx to make a WebSocket connection
        async with client.stream("GET", "ws://localhost:8030/api/v1/qa/ws/test_session_001") as response:
            print(f"  WebSocket response status: {response.status_code}")
            print(f"  Headers: {dict(response.headers)}")

    print()
    print("Test completed")

if __name__ == "__main__":
    try:
        asyncio.run(test_websocket())
    except KeyboardInterrupt:
        print("\nTest interrupted")
    except Exception as e:
        print(f"Error: {e}")