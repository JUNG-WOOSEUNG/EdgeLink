#!/bin/sh
# 개발용 자체 서명 인증서 "EdgeLink Dev"를 로그인 키체인에 만든다.
# 서명이 빌드마다 같아져서 손쉬운 사용·입력 모니터링 권한이 풀리지 않는다. 배포용이 아니다.
set -e
NAME="EdgeLink Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "이미 있어요: $NAME"; exit 0; fi
TMP=$(mktemp -d)
# 중간에 실패해도 개인키가 임시 폴더에 남지 않게
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# 키체인으로 옮기는 동안만 쓰는 일회용 암호 (명령줄 대신 환경 변수로 넘긴다)
EDGELINK_P12_PASS=$(openssl rand -hex 16); export EDGELINK_P12_PASS
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout env:EDGELINK_P12_PASS 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout env:EDGELINK_P12_PASS
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$EDGELINK_P12_PASS" -T /usr/bin/codesign
echo "만들었어요: $NAME (키체인 접근에서 지울 수 있어요)"
