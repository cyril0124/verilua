import os
import json
import argparse

OUTPUT_FILE = "merged.coverage.json"

files = []
coverage_info = {
    "dates": [],
    "simulators": [],
    "nr_cover_points": [],
    "total_cover_point": 0
}

parser = argparse.ArgumentParser(description='A script used for merging verilua coverage.')
parser.add_argument('--file', '-f', action='append', dest="file", help='input coverage file(JSON or filelist).', required=True)
parser.add_argument('--out', '-o', dest="out_file", type=str, default=OUTPUT_FILE, help='output coverage file.')
args = parser.parse_args()

def extract_filelist(file):
    if file.endswith(".f"):
        dirname = os.path.dirname(file)
        filelist = []
        with open(os.path.abspath(file), "r") as f:
            for line in f:
                if line.strip():
                    ff = line.strip()
                    if not os.path.exists(ff):
                        basename = os.path.basename(ff)
                        new_ff = f"{dirname}/{basename}"
                        assert os.path.exists(new_ff), new_ff
                        ff = new_ff
                    else:
                        ff = os.path.abspath(ff)
                    filelist.append(ff)
        s = "\n".join(filelist)
        return filelist
    else:
        return os.path.abspath(file)

# Parse filelist
for f in args.file:
    filelist_or_file = extract_filelist(f)
    if isinstance(filelist_or_file, list):
        for ff in filelist_or_file:
            files.append(ff)
    else:
        assert isinstance(filelist_or_file, str), f"{type(filelist_or_file)}"
        files.append(filelist_or_file)

for f in files:
    with open(f, "r") as json_file:
        data = json.load(json_file)
        assert data["date"] != None
        assert data["simulator"] != None
        assert data["nr_cover_point"] != None

        coverage_info["dates"].append(data["date"])
        coverage_info["simulators"].append(data["simulator"])
        coverage_info["nr_cover_points"].append(data["nr_cover_point"])

        for k, v in data.items():
            if k not in ["date", "simulator", "nr_cover_point"]:
                if coverage_info.get(k) == None:
                    coverage_info["total_cover_point"] += 1
                    coverage_info[k] = 0
                coverage_info[k] += v

with open(args.out_file, "w") as f:
    json.dump(coverage_info, f, indent=4)
