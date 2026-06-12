#!/usr/bin/env python3
"""
PAI-CC WebSocket QA Flow Test
Tests complete AI QA flow: connect -> ask -> streaming -> answer -> TTS
"""
import asyncio
import json
import websockets
import time
from datetime import datetime

# Test configuration
WS_URL = "ws://localhost:8030/api/v1/qa/ws/test_session_001"
TEST_QUERY = "你好，请介绍一下你自己"
ENABLE_TTS = True
VOICE = "af_bella"

# Message types we're expecting
EXPECTED_MESSAGE_TYPES = {
    "thinking": False,      # Initial thinking message
    "partial": [],          # Streaming partial responses (multiple)
    "answer": False,        # Final answer
    "tts_start": False,     # TTS generation started
    "tts_ready": False,     # TTS generation completed
}

test_results = {
    "connection": False,
    "thinking_received": False,
    "partial_count": 0,
    "answer_received": False,
    "final_answer_content": None,
    "tts_started": False,
    "tts_ready": False,
    "tts_audio_url": None,
    "knowledge_points": [],
    "suggested_followups": [],
    "history_length": 0,
    "total_time": 0,
    "errors": []
}

async def test_websocket_qa():
    """Test the complete WebSocket QA flow"""
    start_time = time.time()
    print("=" * 60)
    print("PAI-CC WebSocket QA Flow Test")
    print("=" * 60)
    print(f"Test Session: test_session_001")
    print(f"Query: {TEST_QUERY}")
    print(f"TTS Enabled: {ENABLE_TTS}")
    print()

    try:
        # Step 1: Connect to WebSocket
        print("[1/5] Connecting to WebSocket...")
        async with websockets.connect(WS_URL) as ws:
            test_results["connection"] = True
            print("  [OK] WebSocket connected successfully")
            print()

            # Step 2: Send ask request
            print("[2/5] Sending ask request...")
            ask_message = {
                "type": "ask",
                "query": TEST_QUERY,
                "enable_tts": ENABLE_TTS,
                "voice": VOICE
            }
            await ws.send(json.dumps(ask_message))
            print(f"  [OK] Sent ask message")
            print()

            # Step 3: Receive and verify streaming responses
            print("[3/5] Receiving streaming responses...")
            answer_content = ""
            partial_count = 0
            message_types_received = []

            async for message in ws:
                try:
                    data = json.loads(message)
                    msg_type = data.get("type")
                    message_types_received.append(msg_type)

                    print(f"  [RECV] Type: {msg_type}")

                    if msg_type == "thinking":
                        test_results["thinking_received"] = True
                        print(f"       Status: {data.get('status')}")
                        print(f"       Message: {data.get('message')}")

                    elif msg_type == "partial":
                        partial_count += 1
                        test_results["partial_count"] = partial_count
                        chunk = data.get("content", "")
                        answer_content += chunk
                        # Print first few chunks to show streaming
                        if partial_count <= 3:
                            print(f"       Content (chunk {partial_count}): {chunk[:50]}...")
                        elif partial_count == 4:
                            print(f"       ... ({partial_count} streaming chunks received)")

                    elif msg_type == "answer":
                        test_results["answer_received"] = True
                        test_results["final_answer_content"] = data.get("content", "")
                        test_results["knowledge_points"] = data.get("knowledge_points", [])
                        test_results["suggested_followups"] = data.get("suggested_followups", [])
                        test_results["history_length"] = data.get("history_length", 0)
                        test_results["vision_used"] = data.get("vision_used", False)
                        print(f"       Final answer length: {len(data.get('content', ''))} chars")
                        print(f"       Knowledge points: {data.get('knowledge_points', [])}")
                        print(f"       Suggested followups: {data.get('suggested_followups', [])}")
                        print(f"       History length: {data.get('history_length', 0)}")
                        print(f"       Vision used: {data.get('vision_used', False)}")
                        print()

                    elif msg_type == "tts_start":
                        test_results["tts_started"] = True
                        print(f"       TTS status: {data.get('status')}")
                        print(f"       TTS message: {data.get('message')}")

                    elif msg_type == "tts_ready":
                        test_results["tts_ready"] = True
                        test_results["tts_audio_url"] = data.get("audio_url")
                        print(f"       TTS status: {data.get('status')}")
                        print(f"       TTS audio URL: {data.get('audio_url')}")

                    elif msg_type == "error":
                        test_results["errors"].append(data.get("content", "Unknown error"))
                        print(f"       ERROR: {data.get('content')}")

                    elif msg_type == "interrupted":
                        print(f"       Interrupted by user")

                    else:
                        print(f"       Unknown message type: {msg_type}")

                except json.JSONDecodeError as e:
                    print(f"  [WARN] Failed to parse message: {e}")
                    continue

                # If we received the answer, we can stop listening
                # But wait a bit for TTS completion
                if test_results["answer_received"] and partial_count > 0:
                    # Wait a bit more for TTS response
                    await asyncio.sleep(2)
                    break

        print()
        print("[4/5] Verifying test results...")
        print()

    except websockets.exceptions.ConnectionClosed as e:
        test_results["errors"].append(f"Connection closed: {e}")
        print(f"  [ERROR] WebSocket connection closed: {e}")
    except Exception as e:
        test_results["errors"].append(f"Unexpected error: {e}")
        print(f"  [ERROR] Unexpected error: {e}")

    end_time = time.time()
    test_results["total_time"] = round(end_time - start_time, 2)

    # Print summary
    print("[5/5] Test Summary")
    print("=" * 60)
    print(f"Connection:           {'PASS' if test_results['connection'] else 'FAIL'}")
    print(f"Thinking message:     {'PASS' if test_results['thinking_received'] else 'FAIL'}")
    print(f"Streaming responses:  {'PASS' if test_results['partial_count'] > 0 else 'FAIL'} ({test_results['partial_count']} chunks)")
    print(f"Final answer:        {'PASS' if test_results['answer_received'] else 'FAIL'}")
    print(f"TTS started:          {'PASS' if test_results['tts_started'] else 'FAIL'}")
    print(f"TTS ready:           {'PASS' if test_results['tts_ready'] else 'FAIL'}")
    if test_results['tts_audio_url']:
        print(f"TTS audio URL:        {test_results['tts_audio_url']}")
    print()
    print(f"Total time:           {test_results['total_time']}s")
    print(f"Answer length:        {len(test_results['final_answer_content'] or '')} chars")
    print()
    print(f"Knowledge points:     {test_results['knowledge_points']}")
    print(f"Suggested followups:  {test_results['suggested_followups']}")
    print()

    if test_results['errors']:
        print("Errors encountered:")
        for err in test_results['errors']:
            print(f"  - {err}")
        print()

    # Final verdict
    all_passed = (
        test_results['connection'] and
        test_results['thinking_received'] and
        test_results['partial_count'] > 0 and
        test_results['answer_received'] and
        (not ENABLE_TTS or test_results['tts_ready'])
    )

    print("=" * 60)
    if all_passed:
        print("RESULT: ALL TESTS PASSED")
    else:
        print("RESULT: SOME TESTS FAILED")
    print("=" * 60)

    return test_results

if __name__ == "__main__":
    results = asyncio.run(test_websocket_qa())