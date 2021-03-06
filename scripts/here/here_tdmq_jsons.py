"""\
Generate TDMQ JSONs for loading traffic data.

Takes as input the JSONs generated by HERE_JSON_extractor.
"""

import argparse
import io
import json
import logging
import math
import os
import pickle
import sys

STATION = "HERE"
PROPERTIES = {'jam', 'speed', 'flux', 'length'}
LOG_LEVELS = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
DEFAULT_LOG_LEVEL = "INFO"


class JSONBuilder(object):

    def __init__(self):
        self.nodes = {}
        self.sensors = {}
        self.sensor_types = {}
        for prop in PROPERTIES:
            self.sensor_types[prop] = {
                "name": f"here_{prop}_sensor",
                "controlledProperty": [prop]
            }

    def build_measures(self, info):
        measures = []
        for pos_code, data in info.items():
            node_name = str(pos_code)
            coords = list(reversed(data["coord"]))
            geom = {"type": "Point", "coordinates": coords}
            self.nodes.setdefault(pos_code, {
                "name": node_name,
                "station": STATION,
                "geometry": geom
            })
            for prop in PROPERTIES:
                value = data[prop] if prop != "speed" else data[prop][0]
                if math.isnan(value):
                    continue
                sensor_name = f"{pos_code}.{prop}"
                self.sensors.setdefault(sensor_name, {
                    "name": sensor_name,
                    "type": self.sensor_types[prop]["name"],
                    "node": node_name,
                    "geometry": geom
                })
                measures.append({
                    "time": data["date"],
                    "sensor": sensor_name,
                    "measure": {"value": value}
                })
        return measures


def main(args):
    logging.basicConfig(level=args.log_level)
    try:
        os.makedirs(args.out_dir)
    except FileExistsError:
        pass
    logging.debug("writing to %r", args.out_dir)
    json_builder = JSONBuilder()
    for entry in os.scandir(args.traffic_info_dir):
        dt, ext = os.path.splitext(entry.name)
        if ext != '.pickle':
            continue
        logging.info("processing %r", entry.name)
        with io.open(entry.path, "rb") as f:
            info = pickle.load(f)
        measures = json_builder.build_measures(info)
        fn = os.path.join(args.out_dir, f"measures_{dt}.json")
        with open(fn, "w") as f:
            json.dump({"measures": measures}, f, indent=args.indent)
    for attr in "nodes", "sensors", "sensor_types":
        fn = os.path.join(args.out_dir, f"{attr}.json")
        records = list(getattr(json_builder, attr).values())
        with open(fn, "w") as f:
            json.dump({attr: records}, f, indent=args.indent)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("traffic_info_dir", metavar="TRAFFIC_INFO_DIR",
                        help="dir containing the traffic info JSONs")
    parser.add_argument("-o", "--out-dir", metavar="DIR",
                        default=os.path.join(os.getcwd(), "here_data"))
    parser.add_argument("--indent", metavar="INT", default=4,
                        help="output JSON indentation (n. spaces)")
    parser.add_argument("--log-level", metavar="|".join(LOG_LEVELS),
                        choices=LOG_LEVELS, default=DEFAULT_LOG_LEVEL)
    main(parser.parse_args(sys.argv[1:]))
