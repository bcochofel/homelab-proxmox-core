#!/usr/bin/env python3
import hcl2
import sys

def format_default(value):
    """Return HCL-friendly default value as a string."""
    if isinstance(value, str):
        return f"\"{value}\""
    return str(value)

def generate_example(input_file, output_file):
    with open(input_file, "r") as f:
        data = hcl2.load(f)

    raw_vars = data.get("variable", {})

    # Normalize structure: dict or list
    variables = {}

    if isinstance(raw_vars, dict):
        variables = raw_vars
    elif isinstance(raw_vars, list):
        for entry in raw_vars:
            if isinstance(entry, dict):
                variables.update(entry)
    else:
        raise ValueError("Unsupported HCL structure for variables")

    with open(output_file, "w") as out:
        out.write("# Auto-generated example variables\n\n")

        for var_name, var_body in variables.items():

            # Handle list-wrapped blocks (rare)
            if isinstance(var_body, list):
                var_body = var_body[0]

            default_value = var_body.get("default")

            if default_value is not None:
                # Write commented-out default example
                formatted_default = format_default(default_value)
                out.write(f'#{var_name} = {formatted_default}\n')
            else:
                # Write empty assignment
                out.write(f'{var_name} = ""\n')

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: generate_pkrvars.py <variables.pkr.hcl> <output-file>")
        sys.exit(1)

    generate_example(sys.argv[1], sys.argv[2])
