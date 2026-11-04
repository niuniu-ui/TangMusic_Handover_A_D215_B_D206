"""Append two D206 Chinese piano labels without renumbering any D205 glyph.

The complete original 250-glyph hex and label source are embedded in the
checked-in baseline JSON. Frozen rasters make regeneration independent of
installed fonts; --verify-raster additionally redraws them with the recorded
Windows font and checks the result. No project, renderer or other assets change.
"""
from __future__ import annotations
import argparse
import base64
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tools/reference/d205_font_250_baseline.json"
BASELINE_SHA256 = "7e8c79195c5ee77847d26d296e586edae146c952c910d2abecb3131145b8c38f"
OLD_HEX_SHA256 = "f59979adff5877a64d34bc9a96cf120ddd0688499eed19054fc8533eebfd63d2"
LABELS = {95: "\u673a\u68b0\u94a2\u7434", 96: "\u7535\u5b50\u5408\u6210\u7434"}

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def sha(path: Path) -> str:
    return digest(path.read_bytes())

def label_rows(source: bytes) -> dict[int, bytes]:
    rows = re.findall(rb"^[67]'d(\d+):word=256'h([0-9a-f]{64});\r?$", source, re.M)
    result = {int(index): word for index, word in rows}
    assert len(rows) == len(result), "Duplicate label IDs"
    return result

def decode_rom(source: str) -> tuple[list[int], int]:
    """Independent pROM reader; does not call the generator's packing logic."""
    blocks = re.findall(r"pROM #\((.*?)\) rom(\d+)\(\.DO\(q(\d+)\),\.AD\(\{addr\[9:0\],4'b0\}\)", source, re.S)
    assert len(blocks) == 16, "Font must keep its existing sixteen pROM banks"
    result = []
    for expected_bank, (body, bank, signal) in enumerate(blocks):
        assert int(bank) == int(signal) == expected_bank
        assert ".BIT_WIDTH(16)" in body and ".READ_MODE(1'b0)" in body
        fields = re.findall(r"\.INIT_RAM_([0-9A-F]{2})\(256'h([0-9a-f]{64})\)", body)
        assert len(fields) == 64 and {int(k, 16) for k, _ in fields} == set(range(64))
        # Each independent 256-bit INIT contributes sixteen 16-bit words.
        # Physical addresses concatenate the original low ten address bits
        # with four zero lane bits, retaining every old glyph's location.
        bank_words = [0] * 1024
        for section, bits in fields:
            value = int(bits, 16)
            start = int(section, 16) * 16
            for offset in range(16):
                bank_words[start + offset] = (value >> (offset * 16)) & 0xffff
        result.extend(bank_words)
    assert "input wire [13:0] addr" in source and "bank<=addr[13:10]" in source
    mux = re.findall(r"4'd(\d+):data=q(\d+)\[15:0\];", source)
    assert mux == [(str(i), str(i)) for i in range(16)], "Bank mux changed glyph addresses"
    return result, len(blocks)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Verify current outputs without regenerating them")
    parser.add_argument("--verify-raster", action="store_true", help="Also check the frozen two new glyphs against the original Windows font")
    args = parser.parse_args()
    assert sha(BASELINE) == BASELINE_SHA256, "Frozen self-contained baseline changed"
    meta = json.loads(BASELINE.read_text(encoding="utf-8"))
    original_glyphs = list(meta["glyphs"])
    assert len(original_glyphs) == 250 and meta["original_metadata"]["glyphs"] == meta["glyphs"]
    original_hex = base64.b64decode(meta["baseline_font_hex"]["base64"], validate=True)
    original_text = base64.b64decode(meta["baseline_studio_text"]["base64"], validate=True)
    assert digest(original_hex) == meta["baseline_font_hex"]["sha256"] == OLD_HEX_SHA256
    assert len(original_hex) == meta["baseline_font_hex"]["bytes"] == 96000
    original_words = [int(word, 16) for word in original_hex.split()]
    assert len(original_words) == meta["baseline_font_hex"]["words"] == 250 * 64
    assert digest(original_text) == meta["baseline_studio_text"]["sha256"]
    old_labels = label_rows(original_text)
    assert set(old_labels) == set(range(95)), "All original labels 0..94 must be frozen"
    glyphs = original_glyphs.copy()
    new_words = []
    for expected, entry in zip((250, 251), meta["appended_glyphs"], strict=True):
        assert entry["glyph_index"] == expected and entry["character"] not in glyphs
        words = [int(w, 16) for w in entry["words_hex"]]
        assert len(words) == 64 and any(words)
        assert digest(struct.pack("<64H", *words)) == entry["packed_u16le_sha256"]
        glyphs.append(entry["character"])
        new_words.extend(words)
    assert glyphs[250:] == ["\u68b0", "\u5408"]
    if args.verify_raster:
        from PIL import Image, ImageDraw, ImageFont
        spec = meta["rasterization"]
        font_path = Path(spec["font_file"])
        assert sha(font_path) == spec["font_sha256"], "Installed font differs from the recorded raster source"
        font = ImageFont.truetype(str(font_path), spec["font_size"])
        for entry in meta["appended_glyphs"]:
            image = Image.new("L", tuple(spec["canvas"]))
            ImageDraw.Draw(image).text(tuple(spec["origin"]), entry["character"], font=font, fill=255)
            words = [sum(min(3, image.getpixel((part * 8 + x, y)) * 4 // 256) << (x * 2) for x in range(8)) for y in range(32) for part in range(2)]
            assert words == [int(w, 16) for w in entry["words_hex"]], "Frozen glyph differs from its actual font raster"
    expected_words = original_words + new_words
    # Keep the entire original hex byte prefix, including its CRLF convention.
    expected_hex = original_hex + b"".join(f"{w:04x}\r\n".encode("ascii") for w in new_words)
    additions = b""
    for index, label in LABELS.items():
        ids = [glyphs.index(c) for c in label]
        value = sum(glyph << (column * 8) for column, glyph in enumerate(ids))
        additions += f"7'd{index}:word=256'h{value:064x};\r\n".encode("ascii")
    marker = b"default:word=0;endcase"
    assert original_text.count(marker) == 1
    expected_text = original_text.replace(marker, additions + marker, 1)
    emitter_path = ROOT / "tools/emit_rom.py"
    input_files = [BASELINE, Path(__file__).resolve(), emitter_path]
    inputs = {p.relative_to(ROOT).as_posix(): sha(p) for p in input_files}
    if not args.check_only:
        (ROOT / "assets/studio_font.hex").write_bytes(expected_hex)
        (ROOT / "src/studio_text.vh").write_bytes(expected_text)
        spec = importlib.util.spec_from_file_location("d206_font_emitter", emitter_path)
        emitter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(emitter)
        emitter.ROOT = ROOT
        assert emitter.emit("studio_font", 16, 14, expected_words.copy()) == 16
    actual_hex = (ROOT / "assets/studio_font.hex").read_bytes()
    actual_text = (ROOT / "src/studio_text.vh").read_bytes()
    assert actual_hex == expected_hex and actual_text == expected_text
    assert actual_hex[:len(original_hex)] == original_hex, "An old glyph hex byte changed"
    assert re.sub(rb"^7'd(?:95|96):word=.*\r?\n", b"", actual_text, flags=re.M) == original_text
    current_labels = label_rows(actual_text)
    assert all(current_labels[i] == word for i, word in old_labels.items())
    roundtrips = {}
    for index, label in LABELS.items():
        word = int(current_labels[index], 16)
        ids = [(word >> (i * 8)) & 255 for i in range(len(label))]
        decoded = "".join(glyphs[i] for i in ids)
        assert decoded == label and word >> (8 * len(label)) == 0
        roundtrips[str(index)] = {"text": label, "glyph_indices": ids, "decoded": decoded, "passed": True}
    rom_words, banks = decode_rom((ROOT / "src/studio_font.v").read_text(encoding="ascii"))
    assert rom_words == expected_words + [0] * (16384 - len(expected_words)), "Actual pROM INIT bits do not equal hex"
    assert rom_words[:16000] == original_words
    output_files = [ROOT / p for p in ("src/studio_text.vh", "src/studio_font.v", "assets/studio_font.hex")]
    outputs = {p.relative_to(ROOT).as_posix(): sha(p) for p in output_files}
    fresh = inputs == {p.relative_to(ROOT).as_posix(): sha(p) for p in input_files}
    report = {"passed": True, "fresh": fresh, "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(), "inputs": inputs, "outputs": outputs, "source_sha256": outputs, "baseline_font_hex_sha256": OLD_HEX_SHA256, "baseline_font_hex_bytes": 96000, "baseline_font_word_count": 16000, "glyph_count": len(glyphs), "font_word_count": len(expected_words), "pROM_banks": banks, "old_glyphs_unchanged": True, "old_glyph_hex_prefix_bytes_identical": True, "old_labels_unchanged": True, "rom_matches_hex": True, "rom_address_and_bank_mapping_unchanged": True, "new_glyphs_nonempty": True, "labels": roundtrips, "appended_glyphs": [{"character": entry["character"], "index": entry["glyph_index"], "packed_u16le_sha256": entry["packed_u16le_sha256"]} for entry in meta["appended_glyphs"]], "raster_verified_against_recorded_font": args.verify_raster, "rasterization": meta["rasterization"], "self_contained": "Complete original 250-glyph hex, old label source and new raster words embedded in the pinned tools/reference/d205_font_250_baseline.json; default regeneration needs no external archive, font or Pillow.", "scope": "Append-only font/label data and independent source pROM INIT decoding; no renderer/project changes, synthesis, PnR or hardware validation."}
    assert fresh
    (ROOT / "reports").mkdir(exist_ok=True)
    (ROOT / "reports/font_labels_D206.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "fresh": fresh, "glyph_count": len(glyphs), "font_word_count": len(expected_words), "pROM_banks": banks, "labels": roundtrips, "outputs": outputs}, ensure_ascii=True, indent=2))

if __name__ == "__main__":
    main()
