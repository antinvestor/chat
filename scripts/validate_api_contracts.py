#!/usr/bin/env python3
"""
API Contract Validation Script
Validates API contracts and client compatibility
"""

import json
import sys
import os
import re
from pathlib import Path
from typing import Dict, List, Any

def validate_protobuf_contracts():
    """Validate protobuf contract definitions"""
    
    proto_files = list(Path('lib').rglob('*.proto'))
    
    if not proto_files:
        print("⚠️  No .proto files found - using generated Dart files")
        return validate_generated_dart_contracts()
    
    validation_errors = []
    
    for proto_file in proto_files:
        try:
            with open(proto_file, 'r') as f:
                proto_content = f.read()
            
            # Basic protobuf syntax validation
            if not validate_protobuf_syntax(proto_content):
                validation_errors.append(f"Invalid protobuf syntax in {proto_file}")
            
            # Check for required fields
            if not validate_required_fields(proto_content):
                validation_errors.append(f"Missing required fields in {proto_file}")
                
        except Exception as e:
            validation_errors.append(f"Error reading {proto_file}: {e}")
    
    if validation_errors:
        print("❌ Protobuf validation errors:")
        for error in validation_errors:
            print(f"   - {error}")
        return False
    
    print("✅ Protobuf contracts valid")
    return True

def validate_generated_dart_contracts():
    """Validate generated Dart contract files"""
    
    dart_files = list(Path('lib').rglob('*.pb.dart'))
    
    if not dart_files:
        print("⚠️  No generated .pb.dart files found")
        return True
    
    validation_errors = []
    
    for dart_file in dart_files:
        try:
            with open(dart_file, 'r') as f:
                dart_content = f.read()
            
            # Check for required methods
            required_methods = ['create', 'copyWith', 'toJson', 'fromJson']
            for method in required_methods:
                if f'{method}(' not in dart_content:
                    validation_errors.append(f"Missing method {method} in {dart_file}")
            
            # Check for serialization methods
            if 'writeToBuffer' not in dart_content:
                validation_errors.append(f"Missing serialization in {dart_file}")
                
        except Exception as e:
            validation_errors.append(f"Error reading {dart_file}: {e}")
    
    if validation_errors:
        print("❌ Generated Dart contract validation errors:")
        for error in validation_errors:
            print(f"   - {error}")
        return False
    
    print("✅ Generated Dart contracts valid")
    return True

def validate_api_client_implementations():
    """Validate API client implementations"""
    
    api_clients = [
        'chat_service_client.dart',
        'profile_service_client.dart', 
        'files_service_client.dart',
        'device_service_client.dart',
        'gateway_service_client.dart'
    ]
    
    validation_errors = []
    
    for client_file in api_clients:
        client_path = Path(f'lib/core/networking/{client_file}')
        
        if not client_path.exists():
            validation_errors.append(f"API client {client_file} not found")
            continue
        
        try:
            with open(client_path, 'r') as f:
                client_content = f.read()
            
            # Check for required methods
            required_methods = ['create', 'call', 'stream']
            for method in required_methods:
                if method not in client_content:
                    validation_errors.append(f"Missing method {method} in {client_file}")
            
            # Check for error handling
            if 'try {' not in client_content or 'catch' not in client_content:
                validation_errors.append(f"Missing error handling in {client_file}")
                
        except Exception as e:
            validation_errors.append(f"Error reading {client_file}: {e}")
    
    if validation_errors:
        print("❌ API client validation errors:")
        for error in validation_errors:
            print(f"   - {error}")
        return False
    
    print("✅ API client implementations valid")
    return True

def validate_api_integration():
    """Validate API integration patterns"""
    
    integration_files = list(Path('lib').rglob('*_service.dart'))
    
    validation_errors = []
    
    for integration_file in integration_files:
        try:
            with open(integration_file, 'r') as f:
                integration_content = f.read()
            
            # Check for proper error handling
            if 'safeApiCall' not in integration_content:
                validation_errors.append(f"Missing safeApiCall in {integration_file}")
            
            # Check for token management
            if 'TokenManager' not in integration_content and 'token' not in integration_content:
                validation_errors.append(f"Missing token management in {integration_file}")
            
            # Check for retry logic
            if 'retry' not in integration_content.lower():
                validation_errors.append(f"Missing retry logic in {integration_file}")
                
        except Exception as e:
            validation_errors.append(f"Error reading {integration_file}: {e}")
    
    if validation_errors:
        print("❌ API integration validation errors:")
        for error in validation_errors:
            print(f"   - {error}")
        return False
    
    print("✅ API integration patterns valid")
    return True

def validate_protobuf_syntax(proto_content: str) -> bool:
    """Basic protobuf syntax validation"""
    
    # Check for required syntax declaration
    if 'syntax' not in proto_content:
        return False
    
    # Check for package declaration
    if 'package' not in proto_content:
        return False
    
    # Check for proper message structure
    if 'message' not in proto_content:
        return False
    
    return True

def validate_required_fields(proto_content: str) -> bool:
    """Check for required field definitions"""
    
    # Basic field pattern check
    field_pattern = r'\s+\w+\s+\w+\s*=\s*\d+'
    
    if not re.search(field_pattern, proto_content):
        return False
    
    return True

def generate_api_validation_report():
    """Generate API validation report"""
    
    validation_results = {
        'protobuf_contracts': validate_protobuf_contracts(),
        'api_clients': validate_api_client_implementations(),
        'api_integration': validate_api_integration(),
    }
    
    report = {
        'timestamp': os.environ.get('BUILD_TIMESTAMP', 'unknown'),
        'commit': os.environ.get('GITHUB_SHA', 'unknown'),
        'branch': os.environ.get('GITHUB_REF_NAME', 'unknown'),
        'validation_results': validation_results,
        'status': 'passed' if all(validation_results.values()) else 'failed'
    }
    
    # Save report
    report_path = Path('api_validation/api_validation_report.json')
    report_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"📊 API validation report saved to {report_path}")
    
    return all(validation_results.values())

if __name__ == "__main__":
    print("🔍 Running API contract validation...")
    
    if generate_api_validation_report():
        print("✅ API contract validation passed")
        sys.exit(0)
    else:
        print("❌ API contract validation failed")
        sys.exit(1)
