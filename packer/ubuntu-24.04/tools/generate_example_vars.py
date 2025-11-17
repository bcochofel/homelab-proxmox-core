#!/usr/bin/env python3
# generate_example_vars.py

import hcl2
import sys

with open('variables.pkr.hcl', 'r') as f:
    config = hcl2.load(f)

with open('variables.pkrvars.hcl.example', 'w') as out:
    for var in config.get('variable', []):
        for name, attrs in var.items():
            desc = attrs.get('description', '')
            default = attrs.get('default')

            if desc:
                out.write(f"# {desc}\n")

            if default is not None:
                if isinstance(default, str):
                    out.write(f'{name} = "{default}"\n')
                else:
                    out.write(f'{name} = {default}\n')
            else:
                out.write(f'# {name} = ""\n')

            out.write('\n')
