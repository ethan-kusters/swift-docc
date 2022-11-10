#!/usr/bin/env python3

"""
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
 ------------------------------------------------------------------------------
 This is a helper script for the main swift repository's build-script.py that
 knows how to build and install Swift-DocC given a swift workspace.
"""

import argparse
import json

from openapi_spec_validator import validate_spec
from openapi_spec_validator.readers import read_from_filename
from openapi_spec_validator import openapi_v30_spec_validator

from openapi_schema_validator import validate
from openapi_schema_validator import OAS30Validator
from jsonschema.validators import RefResolver

parser = argparse.ArgumentParser(
    prog = 'openapi-validator',
    description = 'Validates a piece of JSON against an OpenAPI specification.')
    
parser.add_argument('spec', help='The path to a OpenAPI specification.')
parser.add_argument('json', help='The path to the JSON file that will be validated against the given specification.')
parser.add_argument('schema', help='The name of the root schema in the given specification that the JSON should be validated against.')

args = parser.parse_args()

spec_dict, spec_url = read_from_filename(args.spec)
json = json.load(open(args.json))

validate_spec(spec_dict, validator=openapi_v30_spec_validator)

ref_resolver = RefResolver.from_schema(spec_dict)
validate(json, spec_dict["components"]["schemas"][args.schema], cls=OAS30Validator, resolver=ref_resolver)
print("OK")
