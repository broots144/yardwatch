"""Which common central-Indiana yard species have artwork in a fugleramme style.

    uv run python tools/plates/coverage.py --fugleramme ../fugleramme [--style classic]

Reads the style's manifest.json and the vendored alias map so a bird filed under its
current name (astur-cooperii) is matched from BirdNET's older label (Accipiter cooperii).
Prints present and missing lists; exits 0. The missing list is the fetch queue.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# (scientific name as BirdNET labels it, common name). Roughly ordered by feeder frequency.
YARD: list[tuple[str, str]] = [
    ("Cardinalis cardinalis", "Northern Cardinal"),
    ("Cyanocitta cristata", "Blue Jay"),
    ("Poecile carolinensis", "Carolina Chickadee"),
    ("Baeolophus bicolor", "Tufted Titmouse"),
    ("Sitta carolinensis", "White-breasted Nuthatch"),
    ("Dryobates pubescens", "Downy Woodpecker"),
    ("Dryobates villosus", "Hairy Woodpecker"),
    ("Melanerpes carolinus", "Red-bellied Woodpecker"),
    ("Colaptes auratus", "Northern Flicker"),
    ("Spinus tristis", "American Goldfinch"),
    ("Haemorhous mexicanus", "House Finch"),
    ("Haemorhous purpureus", "Purple Finch"),
    ("Passer domesticus", "House Sparrow"),
    ("Zenaida macroura", "Mourning Dove"),
    ("Turdus migratorius", "American Robin"),
    ("Sturnus vulgaris", "European Starling"),
    ("Quiscalus quiscula", "Common Grackle"),
    ("Molothrus ater", "Brown-headed Cowbird"),
    ("Agelaius phoeniceus", "Red-winged Blackbird"),
    ("Thryothorus ludovicianus", "Carolina Wren"),
    ("Troglodytes aedon", "House Wren"),
    ("Junco hyemalis", "Dark-eyed Junco"),
    ("Spizelloides arborea", "American Tree Sparrow"),
    ("Melospiza melodia", "Song Sparrow"),
    ("Zonotrichia albicollis", "White-throated Sparrow"),
    ("Zonotrichia leucophrys", "White-crowned Sparrow"),
    ("Spizella passerina", "Chipping Sparrow"),
    ("Pipilo erythrophthalmus", "Eastern Towhee"),
    ("Pheucticus ludovicianus", "Rose-breasted Grosbeak"),
    ("Passerina cyanea", "Indigo Bunting"),
    ("Sialia sialis", "Eastern Bluebird"),
    ("Dumetella carolinensis", "Gray Catbird"),
    ("Mimus polyglottos", "Northern Mockingbird"),
    ("Toxostoma rufum", "Brown Thrasher"),
    ("Bombycilla cedrorum", "Cedar Waxwing"),
    ("Icterus galbula", "Baltimore Oriole"),
    ("Archilochus colubris", "Ruby-throated Hummingbird"),
    ("Corvus brachyrhynchos", "American Crow"),
    ("Sayornis phoebe", "Eastern Phoebe"),
    ("Sphyrapicus varius", "Yellow-bellied Sapsucker"),
    ("Dryocopus pileatus", "Pileated Woodpecker"),
    ("Accipiter cooperii", "Cooper's Hawk"),
    ("Buteo jamaicensis", "Red-tailed Hawk"),
    ("Cathartes aura", "Turkey Vulture"),
    ("Branta canadensis", "Canada Goose"),
    ("Meleagris gallopavo", "Wild Turkey"),
    ("Chaetura pelagica", "Chimney Swift"),
    ("Hirundo rustica", "Barn Swallow"),
    ("Piranga olivacea", "Scarlet Tanager"),
    ("Setophaga petechia", "Yellow Warbler"),
    ("Geothlypis trichas", "Common Yellowthroat"),
    ("Vireo olivaceus", "Red-eyed Vireo"),
    ("Regulus calendula", "Ruby-crowned Kinglet"),
    ("Polioptila caerulea", "Blue-gray Gnatcatcher"),
    ("Contopus virens", "Eastern Wood-Pewee"),
    ("Tyrannus tyrannus", "Eastern Kingbird"),
    ("Coccyzus americanus", "Yellow-billed Cuckoo"),
    ("Strix varia", "Barred Owl"),
    ("Megascops asio", "Eastern Screech-Owl"),
    ("Bubo virginianus", "Great Horned Owl"),
    ("Charadrius vociferus", "Killdeer"),
    ("Spinus pinus", "Pine Siskin"),
    ("Chordeiles minor", "Common Nighthawk"),
]


def slug(name: str) -> str:
    return name.strip().lower().replace(" ", "-").replace("'", "")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fugleramme", type=Path, required=True, help="path to a fugleramme checkout")
    ap.add_argument("--style", default="classic")
    ap.add_argument("--json", action="store_true", help="emit the missing list as JSON for the fetch tool")
    args = ap.parse_args()

    root = args.fugleramme
    manifest = json.loads((root / "assets/artwork" / args.style / "manifest.json").read_text())
    aliases = json.loads((root / "assets/birdnet_aliases.json").read_text())
    have = {re.sub(r"(-\d+)?\.(webp|png)$", "", k[6:]) for k in manifest if k.startswith("birds/")}

    present, missing = [], []
    for sci, common in YARD:
        current = aliases.get(sci, sci)
        (present if slug(current) in have else missing).append({"scientific": current, "birdnet_label": sci, "common": common})

    if args.json:
        print(json.dumps(missing, indent=1))
        return
    print(f"{args.style}: {len(present)}/{len(YARD)} yard species have artwork")
    print("present:", ", ".join(p["common"] for p in present))
    print("missing:", ", ".join(m["common"] for m in missing))


if __name__ == "__main__":
    main()
