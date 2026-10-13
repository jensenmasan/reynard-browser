import json
import os
from pathlib import Path
import re
import requests

SEMVER_RE = re.compile(r"^\d+(\.\d+)*$")

def gh_request(url: str):
	headers = { 
        "Accept": "application/vnd.github+json",
		"X-GitHub-Api-Version": "2026-03-10",
	}

	token = os.environ.get("GITHUB_TOKEN")
	if token:
		headers["Authorization"] = f"Bearer {token}"

	try:
		response = requests.get(url, headers=headers)
		response.raise_for_status()
	except Exception as error:
		print(f"GitHub request failed for {url}: {error}")
		raise

	return response.json()

def get_build(api_root: str, tag_name: str) -> str:
	ref = gh_request(f"{api_root}/git/ref/tags/{tag_name}")
	target = ref["object"]

	if target["type"] == "tag":
		target = gh_request(target["url"])["object"]

	return target["sha"][:7]

def build_versions(api_root: str, releases: list[dict]) -> list[dict]:
	versions = []

	for release in releases:
		tag_name = release["tag_name"]

		# 只收语义化版本 tag（如 0.16.1）；malaoshi-trollstore-v2 这类旧 tag 无法参与版本比较
		if not SEMVER_RE.match(tag_name):
			continue

		build_version = get_build(api_root, tag_name)

		for asset in release.get("assets", []):
			if not asset.get("name", "").endswith(".tipa"):
				continue

			versions.append(
				{
					"version": tag_name,
					"buildVersion": build_version,
					"date": release["created_at"],
					"localizedDescription": (release.get("body") or "").replace("`", ""),
					"downloadURL": asset["browser_download_url"],
					"size": asset["size"],
				}
			)

	return versions

def main() -> None:
	api_root = "https://api.github.com/repos/jensenmasan/reynard-browser"
	source_path = Path(__file__).with_name("source.json")

	source_data = json.loads(source_path.read_text(encoding="utf-8"))
	source_data["apps"][0]["versions"] = build_versions(api_root, gh_request(f"{api_root}/releases"))

	output = json.dumps(source_data, indent=2)
	json.loads(output)
	source_path.write_text(output, encoding="utf-8")

if __name__ == "__main__":
	main()
