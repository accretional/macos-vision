# How to add a new subcommand to macos-vision cli tool

## Step 1: Info Gathering

1. Read the docs/apple-apis.csv for the relevant url of the Apple document to fetch the details of the subcommand and framework. Make sure we are in objective C implementation. If it is Swift only framework, document it in docs/subcommands/API_NAME.md and stop
2. Collect all the top-level framework index from the document webpage. Go to each framework index and get the properties.
3. Aggregate all the doc links and general info in docs/subcommands/API_NAME.md

## Step 2: Implementation

1. Look at Packages.swift and find the linker framework for the subcommand
2. Implement a thin wrapper of the subcommand. Check out two other subcommands and their implementation styles for reference. Make sure to maintain a similar input/output structure followed by other subcommands.

## Step 3: Testing

1. Write a test file for smoke testing the subcommand and the operations. The run the smoke test script and validate the outputs from the subcommand operations.
2. Go through the sample data files to see if any of them can be used to test the operations. If not, create/add files/data into it for testing. You can either generate it or pull from the internet.
3. Write the subcommand shell script in the examples and run the script. Validate the output generated with the subcommand and the operation.

