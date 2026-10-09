import os
from mini_dfs.globals import CHUNK_SIZE
import json
import base64

def break_file(path):
    output = []
    with open(path, "rb") as f:
        while True:
            res = f.read(CHUNK_SIZE)
            if not res:        
                break
            output.append(res)
    return output

def merge_files(path_list):
    output = ""
    for path in path_list:
        with open(path, "rb") as f:
            res = f.read()
            output += res
    return output

if __name__ == "__main__":
    print(len(break_file("lec1.pdf")))