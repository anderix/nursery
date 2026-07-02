#!/usr/bin/env python3
"""
Split a large CSV file into smaller chunks suitable for upload.
Target size: ~25 MB per chunk (safe for most upload limits)

Author: Claude.ai (Anthropic)
"""

import csv
import os
import sys

# Increase CSV field size limit to handle large fields
maxInt = sys.maxsize
while True:
    try:
        csv.field_size_limit(maxInt)
        break
    except OverflowError:
        maxInt = int(maxInt / 10)

def get_file_size_mb(filename):
    """Get file size in megabytes."""
    return os.path.getsize(filename) / (1024 * 1024)

def split_csv(input_file, target_size_mb=25):
    """
    Split a large CSV file into smaller chunks.
    
    Args:
        input_file: Path to the input CSV file
        target_size_mb: Target size for each chunk in MB (default: 25)
    """
    
    if not os.path.exists(input_file):
        print(f"Error: File '{input_file}' not found.")
        return
    
    # Get input file info
    input_size = get_file_size_mb(input_file)
    print(f"Input file: {input_file}")
    print(f"Size: {input_size:.2f} MB")
    print(f"Target chunk size: {target_size_mb} MB")
    print("-" * 50)
    
    # Prepare output file naming
    base_name = os.path.splitext(input_file)[0]
    
    target_bytes = target_size_mb * 1024 * 1024
    current_chunk = 1
    current_size = 0
    rows_in_chunk = 0
    header = None
    output_file = None
    writer = None
    
    try:
        with open(input_file, 'r', encoding='utf-8', newline='') as infile:
            reader = csv.reader(infile)
            
            # Read header
            header = next(reader)
            header_line = ','.join(f'"{field}"' if ',' in field else field for field in header) + '\n'
            header_size = len(header_line.encode('utf-8'))
            
            # Start first output file
            output_filename = f"{base_name}_part{current_chunk}.csv"
            output_file = open(output_filename, 'w', encoding='utf-8', newline='')
            writer = csv.writer(output_file)
            writer.writerow(header)
            current_size = header_size
            
            print(f"Creating {output_filename}...")
            
            for row in reader:
                # Estimate row size (conservative estimate)
                row_line = ','.join(f'"{field}"' if ',' in field else field for field in row) + '\n'
                row_size = len(row_line.encode('utf-8'))
                
                # Check if adding this row would exceed target size
                if current_size + row_size > target_bytes and rows_in_chunk > 0:
                    # Close current file
                    output_file.close()
                    chunk_size = get_file_size_mb(output_filename)
                    print(f"  ✓ Completed: {rows_in_chunk} rows, {chunk_size:.2f} MB")
                    
                    # Start new file
                    current_chunk += 1
                    output_filename = f"{base_name}_part{current_chunk}.csv"
                    output_file = open(output_filename, 'w', encoding='utf-8', newline='')
                    writer = csv.writer(output_file)
                    writer.writerow(header)
                    current_size = header_size
                    rows_in_chunk = 0
                    print(f"Creating {output_filename}...")
                
                # Write row to current file
                writer.writerow(row)
                current_size += row_size
                rows_in_chunk += 1
            
            # Close final file
            if output_file:
                output_file.close()
                chunk_size = get_file_size_mb(output_filename)
                print(f"  ✓ Completed: {rows_in_chunk} rows, {chunk_size:.2f} MB")
        
        print("-" * 50)
        print(f"Successfully split into {current_chunk} files")
        print(f"\nFiles created:")
        for i in range(1, current_chunk + 1):
            filename = f"{base_name}_part{i}.csv"
            size = get_file_size_mb(filename)
            print(f"  • {filename} ({size:.2f} MB)")
            
    except Exception as e:
        print(f"Error: {e}")
        if output_file and not output_file.closed:
            output_file.close()
        raise

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python csv_splitter.py <input_file.csv> [target_size_mb]")
        print("Example: python csv_splitter.py large_file.csv 25")
        sys.exit(1)
    
    input_file = sys.argv[1]
    target_size = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    
    split_csv(input_file, target_size)
