#!/usr/bin/env python3
"""
Generate variable documentation table for README.md
This script parses variables.pkr.hcl and creates a markdown table.
"""

import hcl2
import sys
import os
import re
from typing import Any, Dict, List

def format_type(var_type: Any) -> str:
    """Format variable type for documentation."""
    if isinstance(var_type, str):
        return f"`{var_type}`"
    elif isinstance(var_type, list):
        # Handle complex types like list(string)
        return f"`{var_type}`"
    else:
        return "`any`"

def format_default(value: Any) -> str:
    """Format default value for documentation."""
    if value is None:
        return "-"
    elif isinstance(value, str):
        # Truncate long strings
        if len(value) > 30:
            return f'`"{value[:27]}..."`'
        return f'`"{value}"`'
    elif isinstance(value, bool):
        return f"`{str(value).lower()}`"
    elif isinstance(value, (int, float)):
        return f"`{value}`"
    elif isinstance(value, list):
        if not value:
            return "`[]`"
        if len(value) <= 3:
            return f"`{value}`"
        return f"`[...{len(value)} items]`"
    elif isinstance(value, dict):
        if not value:
            return "`{}`"
        return "`{...}`"
    else:
        return f"`{value}`"

def is_required(var_attrs: Dict) -> str:
    """Determine if variable is required."""
    default = var_attrs.get('default')
    validation = var_attrs.get('validation', [])

    # If no default and has validation, likely required
    if default is None:
        return "Yes"
    return "No"

def truncate_description(description: str, max_length: int = 80) -> str:
    """Truncate description for table readability."""
    if not description:
        return "-"

    # Clean up description
    description = description.strip().replace('\n', ' ')
    description = re.sub(r'\s+', ' ', description)

    if len(description) <= max_length:
        return description

    return description[:max_length-3] + "..."

def generate_variables_table(input_file: str = 'variables.pkr.hcl') -> str:
    """Generate markdown table of variables."""

    if not os.path.exists(input_file):
        return f"Error: {input_file} not found!"

    try:
        with open(input_file, 'r') as f:
            config = hcl2.load(f)
    except Exception as e:
        return f"Error parsing {input_file}: {e}"

    variables = config.get('variable', [])

    if not variables:
        return "No variables found in the template."

    # Build table
    table = []
    table.append("| Variable | Description | Type | Default | Required |")
    table.append("|----------|-------------|------|---------|----------|")

    # Sort variables alphabetically
    sorted_vars = []
    for var_block in variables:
        for var_name, var_attrs in var_block.items():
            sorted_vars.append((var_name, var_attrs))

    sorted_vars.sort(key=lambda x: x[0])

    for var_name, var_attrs in sorted_vars:
        description = truncate_description(var_attrs.get('description', ''))
        var_type = format_type(var_attrs.get('type', 'any'))
        default = format_default(var_attrs.get('default'))
        required = is_required(var_attrs)

        table.append(f"| `{var_name}` | {description} | {var_type} | {default} | {required} |")

    return '\n'.join(table)

def generate_detailed_variables_section(input_file: str = 'variables.pkr.hcl') -> str:
    """Generate detailed variables documentation with full descriptions."""

    if not os.path.exists(input_file):
        return f"Error: {input_file} not found!"

    try:
        with open(input_file, 'r') as f:
            config = hcl2.load(f)
    except Exception as e:
        return f"Error parsing {input_file}: {e}"

    variables = config.get('variable', [])

    if not variables:
        return "No variables found in the template."

    # Sort variables alphabetically
    sorted_vars = []
    for var_block in variables:
        for var_name, var_attrs in var_block.items():
            sorted_vars.append((var_name, var_attrs))

    sorted_vars.sort(key=lambda x: x[0])

    sections = []

    for var_name, var_attrs in sorted_vars:
        description = var_attrs.get('description', 'No description provided').strip()
        var_type = var_attrs.get('type', 'any')
        default = var_attrs.get('default')
        sensitive = var_attrs.get('sensitive', False)
        validation = var_attrs.get('validation', [])

        section = [f"### `{var_name}`"]
        section.append("")
        section.append(description)
        section.append("")
        section.append(f"- **Type:** `{var_type}`")
        section.append(f"- **Required:** {is_required(var_attrs)}")

        if default is not None:
            section.append(f"- **Default:** {format_default(default)}")

        if sensitive:
            section.append("- **Sensitive:** Yes (value will be hidden in logs)")

        if validation:
            section.append("- **Validation:** Custom validation rules defined")

        section.append("")
        sections.append('\n'.join(section))

    return '\n'.join(sections)

def update_readme(readme_file: str = 'README.md',
                input_file: str = 'variables.pkr.hcl',
                mode: str = 'table'):
    """Update README.md with generated variable documentation."""

    if not os.path.exists(readme_file):
        print(f"Error: {readme_file} not found!", file=sys.stderr)
        sys.exit(1)

    with open(readme_file, 'r') as f:
        content = f.read()

    # Generate the documentation
    if mode == 'detailed':
        var_docs = generate_detailed_variables_section(input_file)
        start_marker = "<!-- VARIABLES_DETAILED_START -->"
        end_marker = "<!-- VARIABLES_DETAILED_END -->"
    else:
        var_docs = generate_variables_table(input_file)
        start_marker = "<!-- VARIABLES_TABLE_START -->"
        end_marker = "<!-- VARIABLES_TABLE_END -->"

    # Check if markers exist
    if start_marker not in content or end_marker not in content:
        print(f"Warning: Markers not found in {readme_file}", file=sys.stderr)
        print(f"Add these markers to your README where you want the {mode} documentation:", file=sys.stderr)
        print(f"\n{start_marker}", file=sys.stderr)
        print(f"{end_marker}\n", file=sys.stderr)
        print("Generated documentation:")
        print(var_docs)
        return

    # Replace content between markers
    pattern = f"{re.escape(start_marker)}.*?{re.escape(end_marker)}"
    replacement = f"{start_marker}\n{var_docs}\n{end_marker}"

    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

    with open(readme_file, 'w') as f:
        f.write(new_content)

    print(f"✓ Updated {readme_file} with {mode} variable documentation")

def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description='Generate variable documentation for Packer templates'
    )
    parser.add_argument(
        '--input',
        default='variables.pkr.hcl',
        help='Input variables file (default: variables.pkr.hcl)'
    )
    parser.add_argument(
        '--output',
        choices=['stdout', 'readme'],
        default='readme',
        help='Output destination (default: readme)'
    )
    parser.add_argument(
        '--readme',
        default='README.md',
        help='README file to update (default: README.md)'
    )
    parser.add_argument(
        '--mode',
        choices=['table', 'detailed'],
        default='table',
        help='Documentation format (default: table)'
    )

    args = parser.parse_args()

    if args.output == 'stdout':
        if args.mode == 'detailed':
            print(generate_detailed_variables_section(args.input))
        else:
            print(generate_variables_table(args.input))
    else:
        update_readme(args.readme, args.input, args.mode)

if __name__ == '__main__':
    main()
