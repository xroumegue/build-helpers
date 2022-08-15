#! /usr/bin/env python

from string import Template
from os import environ
from os.path import splitext
from argparse import ArgumentParser, FileType

parser = ArgumentParser(
        description='Templatize file with default environ variables.')

parser.add_argument('template', type=FileType('r'),
                    help='foo.template Template file')

parser.add_argument('--output', help='Output file')

args = parser.parse_args()

# rootdir = f"{dirname(realpath(__file__))}/.."
# templateFile = rootdir + "/etc/cross-compilation.conf.template"
if args.output is None:
    outputFile = splitext(args.template.name)[0]
else:
    outputFile = args.output

default_variables = dict()
for key in environ:
    if key.endswith('_default'):
        default_variables[key] = environ[key]

with args.template as f:
    s = Template(f.read())
    with open(outputFile, 'w') as out:
        out.write(s.substitute(default_variables))
