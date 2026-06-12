#!/usr/bin/env python3
"""
PAI-CC WebSocket QA Flow Test - Direct websockets test
"""
import asyncio
import json
import time
import sys
sys.path.insert(0, '/home/ydz/projects/pai-cc/backend')

from app.core.config import settings
from app.services.ollama_service import OllamaService

async def test_ollama_stream():
    """Test Ollama streaming directly"""
    print("=" * 60)
    print("Testing Ollama Streaming Service")
    print("=" * 60)
    print()

    service = OllamaService()
    messages = [
        {"role": "system", "content": "你是一个中文学习辅导助手。请用简洁的语言回答。"},
        {"role": "user", "content": "1+1等于几？"}
    ]

    print("Sending streaming request to Ollama...")
    full_response = ""
    chunk_count = 0

    start_time = time.time()
    async for chunk in service.chat_stream(messages):
        chunk_count += 1
        full_response += chunk
        print(f"  Chunk {chunk_count}: {chunk[:30]}...")

    elapsed = time.time() - start_time

    print()
    print("=" * 60)
    print(f"Total chunks received: {chunk_count}")
    print(f"Total response length: {len(full_response)} chars")
    print(f"Time elapsed: {elapsed:.2f}s")
    print(f"Response preview: {full_response[:200]}...")
    print("=" * 60)

    return {
        "chunks": chunk_count,
        "length": len(full_response),
        "time": elapsed,
        "response": full_response
    }

async def test_websocket_connection():
    """Test WebSocket connection to the running server"""
    print()
    print("=" * 60)
    print("Testing WebSocket Connection")
    print("=" * 60)
    print()

    try:
        import websockets
    except ImportError:
        print("Installing websockets...")
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "websockets"], check=True)
        import websockets

    ws_url = "ws://localhost:8030/api/v1/qa/ws/test_session_001"
    print(f"Connecting to: {ws_url}")

    try:
        async with websockets.connect(ws_url, ping_interval=None) as ws:
            print("[OK] Connected successfully")

            # Send ping
            await ws.send(json.dumps({"type": "ping"}))
            print("Sent ping message")

            # Wait for pong
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=5.0)
                print(f"Received: {response}")
            except asyncio.TimeoutError:
                print("Timeout waiting for response")

            # Send ask request
            print()
            print("Sending ask request...")
            ask_msg = {
                "type": "ask",
                "query": "你好，请用一句话介绍你自己",
                "enable_tts": True,
                "voice": "af_bella"
            }
            await ws.send(json.dumps(ask_msg))
            print("Sent ask message, waiting for responses...")

            # Collect responses
            messages = []
            start_time = time.time()

            async for msg in ws:
                messages.append(msg)
                data = json.loads(msg)
                print(f"  [{data.get('type')}] {str(data)[:100]}")

                # If we got the final answer, wait a bit for TTS
                if data.get('type') == 'answer':
                    print("Received final answer, waiting for TTS...")
                    await asyncio.sleep(3)
                    break

                # Timeout after 60 seconds
                if time.time() - start_time > 60:
                    print("Timeout reached")
                    break

            print()
            print(f"Total messages received: {len(messages)}")

            return messages

    except Exception as e:
        print(f"WebSocket error: {e}")
        import traceback
        traceback.print_exc()
        return []

async def test_rest_api_with_tts():
    """Test REST API with TTS enabled"""
    print()
    print("=" * 60)
    print("Testing REST API with TTS")
    print("=" * 60)
    print()

    import httpx

    async with httpx.AsyncClient(timeout=120.0) as client:
        print("Sending request to /api/v1/qa/ask/text-only with TTS enabled...")

        response = await client.post(
            "http://localhost:8030/api/v1/qa/ask/text-only",
            data={
                "query": "请用50字以内介绍一下你自己",
                "session_id": "test_session_001",
                "enable_tts": "true",
                "voice": "af_bella"
            }
        )

        if response.status_code == 200:
            data = response.json()
            print(f"  Answer length: {len(data.get('answer', ''))} chars")
            print(f"  Processing time: {data.get('processing_time', 0):.2f}s")
            print(f"  Audio URL: {data.get('audio_url')}")
            print(f"  Vision supported: {data.get('vision_supported')}")
            print()
            print(f"  Answer preview: {data.get('answer', '')[:150]}...")

            return data
        else:
            print(f"  Error: HTTP {response.status_code}")
            print(response.text)
            return None

async def main():
    results = {
        "ollama_stream": None,
        "websocket": None,
        "rest_api_tts": None
    }

    # Test 1: Ollama streaming
    try:
        results["ollama_stream"] = await test_ollama_stream()
    except Exception as e:
        print(f"Ollama test failed: {e}")
        import traceback
        traceback.print_exc()

    # Test 2: REST API with TTS
    try:
        results["rest_api_tts"] = await test_rest_api_with_tts()
    except Exception as e:
        print(f"REST API TTS test failed: {e}")
        import traceback
        traceback.print_exc()

    # Test 3: WebSocket connection
    try:
        results["websocket"] = await test_websocket_connection()
    except Exception as e:
        print(f"WebSocket test failed: {e}")
        import traceback
        traceback.print_exc()

    # Summary
    print()
    print("=" * 60)
    print("FINAL TEST SUMMARY")
    print("=" * 60)

    if results["ollama_stream"]:
        print(f"Ollama Streaming: PASS ({results['ollama_stream']['chunks']} chunks, {results['ollama_stream']['time']:.1f}s)")

    if results["rest_api_tts"]:
        if results["rest_api_tts"].get("audio_url"):
            print(f"REST API + TTS: PASS (audio_url: {results['rest_api_tts']['audio_url']})")
        else:
            print(f"REST API + TTS: PARTIAL (no audio_url)")

    if results["websocket"]:
        print(f"WebSocket: PASS ({len(results['websocket'])} messages)")
    else:
        print("WebSocket: FAIL (connection failed)")

    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(main())