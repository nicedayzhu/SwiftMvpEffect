#!/usr/bin/env python3
"""Audit Source 2 overlay VPCF sources for layering and template mistakes."""

from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import re
import sys
from dataclasses import asdict, dataclass


UNRESOLVED_RE = re.compile(r"\{\{[A-Z0-9_]+\}\}")
DEPTH_SORT_RE = re.compile(
    r"\bm_flDepthSortBias\s*=\s*(-?(?:\d+(?:\.\d*)?|\.\d+))"
)
RENDERER_DEPTH_RE = re.compile(
    r"\bm_flDepthBias\s*=\s*\{.*?"
    r"\bm_flLiteralValue\s*=\s*(-?(?:\d+(?:\.\d*)?|\.\d+)).*?\}",
    re.DOTALL,
)
TEXTURE_RE = re.compile(r'm_hTexture\s*=\s*resource:"([^"]+)"')
CHILD_RE = re.compile(r'm_ChildRef\s*=\s*resource:"([^"]+)"')
OVERLAY_RE = re.compile(
    r"\bm_bOnlyRenderInEffecsGameOverlay\s*=\s*true\b",
    re.IGNORECASE,
)


@dataclass
class Audit:
    path: str
    overlay: bool
    root_candidate: bool
    depth_sort_bias: float | None
    renderer_depth_biases: list[float]
    children: list[str]
    textures: list[str]
    unresolved_tokens: list[str]
    errors: list[str]
    warnings: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="+",
        type=pathlib.Path,
        help="VPCF files or directories to scan recursively.",
    )
    parser.add_argument(
        "--root-pattern",
        action="append",
        default=["*root*.vpcf"],
        help=(
            "Filename glob identifying independently spawned roots. "
            "Repeat for additional patterns. Default: *root*.vpcf"
        ),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail when an overlay root candidate has no m_flDepthSortBias.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON instead of a compact text report.",
    )
    return parser.parse_args()


def collect_files(paths: list[pathlib.Path]) -> list[pathlib.Path]:
    found: set[pathlib.Path] = set()
    for supplied in paths:
        path = supplied.resolve()
        if path.is_file():
            if path.suffix.lower() == ".vpcf":
                found.add(path)
            continue
        if path.is_dir():
            found.update(item.resolve() for item in path.rglob("*.vpcf"))
            continue
        raise FileNotFoundError(path)
    return sorted(found, key=lambda item: str(item).lower())


def audit_file(
    path: pathlib.Path,
    root_patterns: list[str],
    strict: bool,
) -> Audit:
    text = path.read_text(encoding="utf-8")
    unresolved = sorted(set(UNRESOLVED_RE.findall(text)))
    sort_match = DEPTH_SORT_RE.search(text)
    root_candidate = any(
        fnmatch.fnmatch(path.name.lower(), pattern.lower())
        for pattern in root_patterns
    )
    overlay = bool(OVERLAY_RE.search(text))
    errors: list[str] = []
    warnings: list[str] = []

    if unresolved:
        errors.append("unresolved template token(s)")
    if overlay and root_candidate and sort_match is None:
        message = "overlay root candidate has no system m_flDepthSortBias"
        (errors if strict else warnings).append(message)

    children = CHILD_RE.findall(text)
    duplicate_children = sorted(
        child for child in set(children) if children.count(child) > 1
    )
    if duplicate_children:
        warnings.append("duplicate child reference(s)")

    return Audit(
        path=str(path),
        overlay=overlay,
        root_candidate=root_candidate,
        depth_sort_bias=(
            float(sort_match.group(1)) if sort_match is not None else None
        ),
        renderer_depth_biases=[
            float(value) for value in RENDERER_DEPTH_RE.findall(text)
        ],
        children=children,
        textures=TEXTURE_RE.findall(text),
        unresolved_tokens=unresolved,
        errors=errors,
        warnings=warnings,
    )


def text_report(audits: list[Audit]) -> None:
    overlay_count = sum(item.overlay for item in audits)
    root_count = sum(item.root_candidate for item in audits)
    print(
        f"Scanned {len(audits)} VPCF source(s): "
        f"{overlay_count} overlay, {root_count} root candidate(s)."
    )
    for item in audits:
        if not (
            item.root_candidate
            or item.errors
            or item.warnings
        ):
            continue
        sort_value = (
            "missing"
            if item.depth_sort_bias is None
            else f"{item.depth_sort_bias:g}"
        )
        flags = []
        if item.errors:
            flags.append("ERROR=" + "; ".join(item.errors))
        if item.warnings:
            flags.append("WARN=" + "; ".join(item.warnings))
        suffix = " | " + " | ".join(flags) if flags else ""
        print(
            f"{item.path} | overlay={item.overlay} "
            f"| sort={sort_value} | renderer={item.renderer_depth_biases} "
            f"| children={len(item.children)} | textures={len(item.textures)}"
            f"{suffix}"
        )


def main() -> int:
    args = parse_args()
    audits = [
        audit_file(path, args.root_pattern, args.strict)
        for path in collect_files(args.paths)
    ]
    if args.json:
        print(json.dumps([asdict(item) for item in audits], indent=2))
    else:
        text_report(audits)

    errors = sum(len(item.errors) for item in audits)
    warnings = sum(len(item.warnings) for item in audits)
    if not args.json:
        print(f"Result: {errors} error(s), {warnings} warning(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
