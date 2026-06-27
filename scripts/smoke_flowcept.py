"""
smoke_flowcept.py — minimal check that Flowcept captures and persists a workflow.
Run AFTER `docker compose up -d redis mongo` and `pip install flowcept`.

If this prints captured task docs, Stage 1 is good and you can start building the
C1 attestation extension. If it errors or stores nothing, fix that before anything
downstream — every later stage assumes Flowcept capture works.

This is a generic shape; adjust import names to the installed Flowcept version,
whose API may differ. Treat it as a checklist, not gospel:
  1. Flowcept starts and connects to Redis + MongoDB.
  2. A decorated function's execution is captured as provenance.
  3. The captured provenance is queryable from the DB.
"""

import os
from dotenv import load_dotenv

load_dotenv()

def main():
    try:
        from flowcept import Flowcept, flowcept_task
    except Exception as e:
        raise SystemExit(
            f"Could not import Flowcept ({e}). "
            "Confirm `pip install flowcept` succeeded in this venv."
        )

    @flowcept_task
    def add(a, b):
        return a + b

    @flowcept_task
    def scale(x, factor=2):
        return x * factor

    with Flowcept(workflow_name="smoke_test"):
        s = add(2, 3)
        _ = scale(s, factor=10)

    # Query back what was captured. The exact query API varies by version;
    # this is the check you care about: did anything land in the store?
    try:
        from flowcept import TaskQueryAPI
        docs = TaskQueryAPI().query(filter={"workflow_name": "smoke_test"})
        print(f"Captured {len(docs)} task document(s).")
        for d in docs:
            print("  -", d.get("activity_id"), d.get("used"), d.get("generated"))
        if not docs:
            print("WARNING: capture ran but nothing was stored — check Mongo/Redis.")
    except Exception as e:
        print(f"Capture ran, but query-back failed ({e}). "
              "Check the installed version's query API and Mongo connectivity.")


if __name__ == "__main__":
    main()
