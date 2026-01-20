#!/usr/bin/env python3
"""
Documentation Coverage Check Script
Validates documentation coverage and quality
"""

import json
import sys
import os
import re
from pathlib import Path
from typing import Dict, List, Any

# Documentation thresholds
DOC_THRESHOLDS = {
    'public_api_coverage': 90,     # percentage
    'class_doc_coverage': 80,      # percentage
    'method_doc_coverage': 75,     # percentage
    'example_coverage': 50,        # percentage
}

def analyze_dart_documentation():
    """Analyze Dart code documentation coverage"""
    
    dart_files = list(Path('lib').rglob('*.dart'))
    
    if not dart_files:
        print("❌ No Dart files found")
        return False
    
    total_classes = 0
    documented_classes = 0
    total_methods = 0
    documented_methods = 0
    total_public_apis = 0
    documented_public_apis = 0
    
    for dart_file in dart_files:
        try:
            with open(dart_file, 'r') as f:
                content = f.read()
            
            # Skip generated files
            if '.g.dart' in dart_file.name or '.pb.dart' in dart_file.name:
                continue
            
            # Analyze classes
            classes = re.findall(r'class\s+(\w+)', content)
            total_classes += len(classes)
            
            for class_name in classes:
                class_pattern = rf'class\s+{class_name}\s*\{{[^}}]*///'
                if re.search(class_pattern, content, re.DOTALL):
                    documented_classes += 1
            
            # Analyze methods
            methods = re.findall(r'\s*(\w+)\s*\([^)]*\)\s*(?:\w+\s+)?\{', content)
            total_methods += len(methods)
            
            # Count documented methods (those with /// before them)
            documented_method_pattern = r'///[^\n]*\n\s*\w+\s*\([^)]*\)'
            documented_methods += len(re.findall(documented_method_pattern, content))
            
            # Analyze public APIs (public classes and methods)
            public_classes = re.findall(r'class\s+(\w+)', content)
            public_methods = re.findall(r'\s*(\w+)\s*\([^)]*\)\s*(?:\w+\s+)?\{', content)
            
            total_public_apis += len(public_classes) + len(public_methods)
            
            # Count documented public APIs
            doc_public_classes = len(re.findall(r'class\s+\w+\s*\{[^}]*///', content, re.DOTALL))
            doc_public_methods = len(re.findall(r'///[^\n]*\n\s*\w+\s*\([^)]*\)', content))
            documented_public_apis += doc_public_classes + doc_public_methods
            
        except Exception as e:
            print(f"⚠️  Error analyzing {dart_file}: {e}")
    
    # Calculate coverage percentages
    class_coverage = (documented_classes / total_classes * 100) if total_classes > 0 else 0
    method_coverage = (documented_methods / total_methods * 100) if total_methods > 0 else 0
    public_api_coverage = (documented_public_apis / total_public_apis * 100) if total_public_apis > 0 else 0
    
    print(f"📊 Documentation Coverage Analysis:")
    print(f"   Classes: {documented_classes}/{total_classes} ({class_coverage:.1f}%)")
    print(f"   Methods: {documented_methods}/{total_methods} ({method_coverage:.1f}%)")
    print(f"   Public APIs: {documented_public_apis}/{total_public_apis} ({public_api_coverage:.1f}%)")
    
    # Check thresholds
    failed_checks = []
    
    if public_api_coverage < DOC_THRESHOLDS['public_api_coverage']:
        failed_checks.append(f"Public API coverage {public_api_coverage:.1f}% < {DOC_THRESHOLDS['public_api_coverage']}%")
    
    if class_coverage < DOC_THRESHOLDS['class_doc_coverage']:
        failed_checks.append(f"Class coverage {class_coverage:.1f}% < {DOC_THRESHOLDS['class_doc_coverage']}%")
    
    if method_coverage < DOC_THRESHOLDS['method_doc_coverage']:
        failed_checks.append(f"Method coverage {method_coverage:.1f}% < {DOC_THRESHOLDS['method_doc_coverage']}%")
    
    if failed_checks:
        print("❌ Documentation coverage thresholds not met:")
        for check in failed_checks:
            print(f"   - {check}")
        return False
    
    print("✅ Documentation coverage meets thresholds")
    return True

def check_example_coverage():
    """Check for code examples in documentation"""
    
    dart_files = list(Path('lib').rglob('*.dart'))
    
    total_documented_items = 0
    items_with_examples = 0
    
    for dart_file in dart_files:
        try:
            with open(dart_file, 'r') as f:
                content = f.read()
            
            # Skip generated files
            if '.g.dart' in dart_file.name or '.pb.dart' in dart_file.name:
                continue
            
            # Find documentation blocks
            doc_blocks = re.findall(r'///[^{]*?(?=\n\s*(?:class|abstract|void|bool|int|String|List|Map|Future|Stream))', content, re.DOTALL)
            
            for doc_block in doc_blocks:
                total_documented_items += 1
                
                # Check for examples
                if '```dart' in doc_block or 'Example:' in doc_block:
                    items_with_examples += 1
                    
        except Exception as e:
            print(f"⚠️  Error checking examples in {dart_file}: {e}")
    
    example_coverage = (items_with_examples / total_documented_items * 100) if total_documented_items > 0 else 0
    
    print(f"📝 Example Coverage: {items_with_examples}/{total_documented_items} ({example_coverage:.1f}%)")
    
    if example_coverage < DOC_THRESHOLDS['example_coverage']:
        print(f"❌ Example coverage {example_coverage:.1f}% < {DOC_THRESHOLDS['example_coverage']}%")
        return False
    
    print("✅ Example coverage meets threshold")
    return True

def validate_documentation_quality():
    """Validate documentation quality standards"""
    
    dart_files = list(Path('lib').rglob('*.dart'))
    
    quality_issues = []
    
    for dart_file in dart_files:
        try:
            with open(dart_file, 'r') as f:
                content = f.read()
            
            # Skip generated files
            if '.g.dart' in dart_file.name or '.pb.dart' in dart_file.name:
                continue
            
            # Check for documentation blocks
            doc_blocks = re.findall(r'///.*?(?=\n\s*(?:class|abstract|void|bool|int|String|List|Map|Future|Stream))', content, re.DOTALL)
            
            for doc_block in doc_blocks:
                # Check for parameter documentation
                if '```dart' in doc_block:
                    # Check if example has proper structure
                    if 'final' not in doc_block and 'var' not in doc_block:
                        quality_issues.append(f"Poor example structure in {dart_file}")
                
                # Check for return type documentation
                if 'Returns:' not in doc_block and 'return' in doc_block.lower():
                    quality_issues.append(f"Missing return documentation in {dart_file}")
                
                # Check for parameter documentation
                if 'Parameters:' not in doc_block and ('@param' in doc_block or 'param:' in doc_block.lower()):
                    quality_issues.append(f"Inconsistent parameter documentation in {dart_file}")
                    
        except Exception as e:
            print(f"⚠️  Error checking quality in {dart_file}: {e}")
    
    if quality_issues:
        print("❌ Documentation quality issues found:")
        for issue in quality_issues[:10]:  # Limit output
            print(f"   - {issue}")
        if len(quality_issues) > 10:
            print(f"   ... and {len(quality_issues) - 10} more issues")
        return False
    
    print("✅ Documentation quality meets standards")
    return True

def generate_documentation_report():
    """Generate documentation analysis report"""
    
    analysis_results = {
        'dart_documentation': analyze_dart_documentation(),
        'example_coverage': check_example_coverage(),
        'documentation_quality': validate_documentation_quality(),
    }
    
    report = {
        'timestamp': os.environ.get('BUILD_TIMESTAMP', 'unknown'),
        'commit': os.environ.get('GITHUB_SHA', 'unknown'),
        'branch': os.environ.get('GITHUB_REF_NAME', 'unknown'),
        'thresholds': DOC_THRESHOLDS,
        'analysis_results': analysis_results,
        'status': 'passed' if all(analysis_results.values()) else 'failed'
    }
    
    # Save report
    report_path = Path('test_results/documentation_report.json')
    report_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"📊 Documentation report saved to {report_path}")
    
    return all(analysis_results.values())

if __name__ == "__main__":
    print("📚 Running documentation analysis...")
    
    if generate_documentation_report():
        print("✅ Documentation analysis passed")
        sys.exit(0)
    else:
        print("❌ Documentation analysis failed")
        sys.exit(1)
