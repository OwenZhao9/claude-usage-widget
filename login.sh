#!/bin/bash
# 浮窗登录：OAuth 授权（含 user:profile），凭证存进浮窗 Keychain。
cd "$(dirname "$0")"
exec swift run Login
