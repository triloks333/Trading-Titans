#!/usr/bin/env python3
"""
Trading Titans - iOS Certificate & Credential Assistant for Windows
===================================================================
This script generates the Certificate Signing Request (CSR) and converts
your downloaded Apple Distribution Certificate into a .p12 certificate
ready for GitHub Actions cloud building.

Requirements:
  - Git for Windows (OpenSSL included at C:\\Program Files\\Git\\usr\\bin\\openssl.exe)
"""

import os
import subprocess
import sys
import base64
from pathlib import Path

OPENSSL_PATH = r"C:\Program Files\Git\usr\bin\openssl.exe"
if not os.path.exists(OPENSSL_PATH):
    # Try system PATH
    OPENSSL_PATH = "openssl"

OUT_DIR = Path("ios_secrets")
OUT_DIR.mkdir(exist_ok=True)

def step1_generate_csr():
    print("=" * 70)
    print("STEP 1: Generate Certificate Signing Request (CSR)")
    print("=" * 70)
    email = input("Enter your Apple ID email (e.g. name@example.com): ").strip()
    name = input("Enter your Full Name (or Company Name): ").strip()

    key_file = OUT_DIR / "ios_distribution.key"
    csr_file = OUT_DIR / "ios_distribution.csr"

    cmd = [
        OPENSSL_PATH, "req", "-nodes", "-newkey", "rsa:2048",
        "-keyout", str(key_file),
        "-out", str(csr_file),
        "-subj", f"/emailAddress={email}, CN={name}, C=IN"
    ]

    print(f"\nGenerating private key and CSR in '{OUT_DIR}'...")
    subprocess.run(cmd, check=True)

    print("\n✅ Private key and CSR generated successfully!")
    print(f"   Private Key: {key_file}")
    print(f"   CSR File:    {csr_file}")
    print("\nNext Action in Browser:")
    print("1. Go to: https://developer.apple.com/account/resources/certificates/add")
    print("2. Select 'Apple Distribution' (or 'iOS Distribution') and click Continue.")
    print(f"3. Upload the file: {csr_file.resolve()}")
    print("4. Click Generate and Download your 'distribution.cer' file.")
    print(f"5. Move the downloaded 'distribution.cer' into the '{OUT_DIR}' folder.")
    print("6. Run this script again with: python scripts/generate_ios_credentials.py --step2")

def step2_convert_to_p12():
    print("=" * 70)
    print("STEP 2: Convert Certificate to .p12 & Base64 for GitHub Secrets")
    print("=" * 70)

    cer_file = OUT_DIR / "distribution.cer"
    key_file = OUT_DIR / "ios_distribution.key"
    pem_file = OUT_DIR / "distribution.pem"
    p12_file = OUT_DIR / "ios_distribution.p12"

    if not cer_file.exists():
        print(f"❌ Error: Could not find '{cer_file}'.")
        print(f"Please download your certificate from developer.apple.com and place it at: {cer_file.resolve()}")
        sys.exit(1)

    password = input("Enter a password to protect your .p12 certificate (remember this!): ").strip()
    if not password:
        password = "TradingTitans2026!"
        print(f"Using default password: {password}")

    # Convert DER to PEM
    subprocess.run([
        OPENSSL_PATH, "x509", "-in", str(cer_file),
        "-inform", "DER", "-out", str(pem_file), "-outform", "PEM"
    ], check=True)

    # Export PKCS#12
    subprocess.run([
        OPENSSL_PATH, "pkcs12", "-export",
        "-inkey", str(key_file),
        "-in", str(pem_file),
        "-out", str(p12_file),
        "-passout", f"pass:{password}"
    ], check=True)

    print("\n✅ Successfully created:", p12_file)

    # Output base64
    p12_b64 = base64.b64encode(p12_file.read_bytes()).decode("utf-8")
    b64_file = OUT_DIR / "p12_base64.txt"
    b64_file.write_text(p12_b64, encoding="utf-8")

    print("\n" + "=" * 70)
    print("COPY THESE VALUES TO GITHUB SECRETS (Repository -> Settings -> Secrets -> Actions):")
    print("=" * 70)
    print(f"1. APPLE_CERTIFICATE_BASE64: Saved to '{b64_file}'")
    print(f"2. APPLE_CERTIFICATE_PASSWORD: {password}")
    print("\nNext: Download your App Store Provisioning Profile (.mobileprovision) from:")
    print("https://developer.apple.com/account/resources/profiles/list")
    print("Encode it to Base64 and add it as APPLE_PROVISIONING_PROFILE_BASE64.")
    print("=" * 70)

if __name__ == "__main__":
    if "--step2" in sys.argv:
        step2_convert_to_p12()
    else:
        step1_generate_csr()
