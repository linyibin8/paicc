#!/usr/bin/env python3
"""
PAI-CC Gesture Interrupt and End Test
Tests: interrupt=OK gesture, clear=peace gesture

Flow:
1. Start QA process (connect to WebSocket)
2. Send interrupt signal (OK gesture simulation)
3. Verify interrupted response
4. Send new ask
5. Send clear signal (peace gesture simulation)
6. Verify history cleared
"""
import asyncio
import json
import websockets
import time
from datetime import datetime

# Test configuration
WS_URL = "ws://localhost:8030/api/v1/qa/ws/gesture_test_session"
TEST_QUERY_1 = "请介绍一下太阳系有哪些行星"
TEST_QUERY_2 = "地球距离太阳有多远"

test_results = {
    "connection": False,
    "ask_1_sent": False,
    "ask_1_interrupted": False,
    "interrupted_response": None,
    "ask_2_sent": False,
    "ask_2_completed": False,
    "clear_sent": False,
    "history_cleared": False,
    "final_history_length": None,
    "errors": [],
    "messages": []
}

def log(msg):
    """Log with timestamp"""
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    print(f"[{ts}] {msg}")
    test_results["messages"].append(f"[{ts}] {msg}")

async def test_gesture_interrupt_and_clear():
    """Test gesture interrupt (OK) and clear (peace) functions"""
    print("=" * 70)
    print("PAI-CC Gesture Interrupt and End Test")
    print("=" * 70)
    print(f"Test: interrupt=OK gesture, clear=peace gesture")
    print(f"Session: gesture_test_session")
    print()

    async with websockets.connect(WS_URL) as ws:
        test_results["connection"] = True
        log("[PASS] WebSocket connected successfully")

        # Step 1: Send first ask query
        log("[STEP 1] Sending first ask query...")
        await ws.send(json.dumps({
            "type": "ask",
            "query": TEST_QUERY_1,
            "enable_tts": False  # Disable TTS for faster test
        }))
        test_results["ask_1_sent"] = True
        log(f"       Query: {TEST_QUERY_1}")

        # Step 2: Receive some partial responses, then interrupt
        log("[STEP 2] Receiving partial responses, then simulating interrupt...")
        partial_content = ""
        answer_received = False

        async for message in ws:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "thinking":
                    log(f"       [thinking] {data.get('message', '')}")

                elif msg_type == "partial":
                    chunk = data.get("content", "")
                    partial_content += chunk
                    # Simulate interrupt after receiving a few chunks
                    if len(partial_content) > 50 and not test_results["ask_1_interrupted"]:
                        test_results["ask_1_interrupted"] = True
                        log(f"       [partial] Received {len(partial_content)} chars")
                        log(f"       >>> SENDING INTERRUPT SIGNAL (OK gesture simulation)")

                        # Send interrupt
                        await ws.send(json.dumps({
                            "type": "interrupt",
                            "session_id": "gesture_test_session"
                        }))
                        log(f"       [interrupt] Signal sent")

                elif msg_type == "interrupted":
                    test_results["interrupted_response"] = "interrupted"
                    log(f"       [interrupted] Server acknowledged interrupt")
                    log(f"       Message: {data.get('message', '')}")
                    # Break after receiving interrupt confirmation
                    break

                elif msg_type == "answer":
                    answer_received = True
                    log(f"       [answer] Received full answer (interrupt not sent in time)")

                elif msg_type == "error":
                    log(f"       [error] {data.get('content', '')}")

            except json.JSONDecodeError:
                continue

        # Small delay before sending second query
        await asyncio.sleep(0.5)

        # Step 3: Verify interrupt was received
        log("[STEP 3] Verifying interrupt response...")
        if test_results["ask_1_interrupted"]:
            log(f"       [PASS] Interrupt signal was sent")
        else:
            log(f"       [INFO] Interrupt not sent (answer completed before interrupt)")

        # Step 4: Send second ask query
        log("[STEP 4] Sending second ask query (after interrupt)...")
        await ws.send(json.dumps({
            "type": "ask",
            "query": TEST_QUERY_2,
            "enable_tts": False
        }))
        test_results["ask_2_sent"] = True
        log(f"       Query: {TEST_QUERY_2}")

        # Step 5: Wait for answer completion
        log("[STEP 5] Waiting for second answer to complete...")
        answer_2_content = ""

        async for message in ws:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "thinking":
                    log(f"       [thinking] {data.get('message', '')}")

                elif msg_type == "partial":
                    chunk = data.get("content", "")
                    answer_2_content += chunk

                elif msg_type == "answer":
                    test_results["ask_2_completed"] = True
                    log(f"       [answer] Answer completed, length: {len(answer_2_content)} chars")
                    log(f"       Knowledge points: {data.get('knowledge_points', [])}")
                    log(f"       History length: {data.get('history_length', 0)}")
                    test_results["history_length_after_ask_2"] = data.get("history_length", 0)
                    break

                elif msg_type == "error":
                    log(f"       [error] {data.get('content', '')}")

            except json.JSONDecodeError:
                continue

        # Small delay
        await asyncio.sleep(0.5)

        # Step 6: Send clear signal (peace gesture simulation)
        log("[STEP 6] Sending clear signal (peace gesture simulation)...")
        await ws.send(json.dumps({
            "type": "clear",
            "session_id": "gesture_test_session"
        }))
        test_results["clear_sent"] = True
        log(f"       [clear] Signal sent")

        # Step 7: Wait for cleared response
        log("[STEP 7] Waiting for cleared confirmation...")
        async for message in ws:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "cleared":
                    test_results["history_cleared"] = True
                    log(f"       [cleared] Server confirmed history cleared")
                    log(f"       Status: {data.get('status', '')}")
                    log(f"       Message: {data.get('message', '')}")
                    break

            except json.JSONDecodeError:
                continue

        # Step 8: Verify history is cleared by requesting history
        log("[STEP 8] Verifying history is cleared...")
        await ws.send(json.dumps({
            "type": "get_history",
            "session_id": "gesture_test_session"
        }))
        log(f"       [get_history] Request sent")

        async for message in ws:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "history_update":
                    history = data.get("history", [])
                    test_results["final_history_length"] = len(history)
                    log(f"       [history_update] History length: {len(history)}")
                    if len(history) == 0:
                        log(f"       [PASS] History is empty - clear successful!")
                    else:
                        log(f"       [FAIL] History still has {len(history)} messages")
                    break

            except json.JSONDecodeError:
                continue

    return test_results

async def main():
    """Run all tests and print summary"""
    try:
        results = await test_gesture_interrupt_and_clear()
    except Exception as e:
        results = test_results
        results["errors"].append(str(e))
        log(f"[ERROR] Test failed with exception: {e}")

    # Print summary
    print()
    print("=" * 70)
    print("TEST RESULTS SUMMARY")
    print("=" * 70)

    checks = [
        ("WebSocket Connection", results.get("connection", False)),
        ("First Ask Sent", results.get("ask_1_sent", False)),
        ("Interrupt Signal Sent", results.get("ask_1_interrupted", False)),
        ("Interrupt Response Received", results.get("interrupted_response") == "interrupted"),
        ("Second Ask Sent", results.get("ask_2_sent", False)),
        ("Second Answer Completed", results.get("ask_2_completed", False)),
        ("Clear Signal Sent", results.get("clear_sent", False)),
        ("History Cleared Confirmation", results.get("history_cleared", False)),
        ("History Length Verified", results.get("final_history_length") == 0),
    ]

    passed = 0
    failed = 0
    for name, result in checks:
        status = "PASS" if result else "FAIL"
        symbol = "[PASS]" if result else "[FAIL]"
        print(f"{symbol} {name}")
        if result:
            passed += 1
        else:
            failed += 1

    print()
    print(f"Total: {passed} passed, {failed} failed")

    if results.get("errors"):
        print()
        print("Errors encountered:")
        for err in results["errors"]:
            print(f"  - {err}")

    print()
    print("=" * 70)
    if failed == 0:
        print("FINAL RESULT: ALL TESTS PASSED")
    else:
        print(f"FINAL RESULT: {failed} TEST(S) FAILED")
    print("=" * 70)

    # Return exit code
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)