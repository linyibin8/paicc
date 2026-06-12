#!/usr/bin/env python3
"""WebSocket QA 测试工具"""
import asyncio
import json
import websockets
import sys

WS_URL = "ws://100.64.0.13:8030/api/v1/qa/ws/test-session-001"

async def test_websocket():
    print(f"🔌 连接到: {WS_URL}")
    try:
        async with websockets.connect(WS_URL, ping_interval=30) as ws:
            print("✅ WebSocket 连接成功!")
            
            # 连接消息
            await ws.send(json.dumps({"type": "connect", "client": "ios", "version": "1.0"}))
            print("📤 发送连接消息")
            
            response = await asyncio.wait_for(ws.recv(), timeout=5)
            print(f"📥 收到: {response}")
            
            # 发送问答
            await ws.send(json.dumps({"type": "ask", "query": "你好", "enable_tts": False}))
            print("📤 发送问答请求")
            
            # 接收响应
            while True:
                try:
                    response = await asyncio.wait_for(ws.recv(), timeout=60)
                    data = json.loads(response)
                    msg_type = data.get("type", "unknown")
                    print(f"📥 收到类型: {msg_type}")
                    
                    if msg_type in ["complete", "answer"]:
                        print(f"✅ 回答: {data.get('content', '')[:100]}...")
                        break
                    elif msg_type == "error":
                        print(f"❌ 错误: {data.get('content')}")
                        break
                except asyncio.TimeoutError:
                    print("⏰ 超时")
                    break
            print("\n🎉 测试完成!")
    except Exception as e:
        print(f"❌ 错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(test_websocket())
