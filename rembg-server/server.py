import io
from PIL import Image
from flask import Flask, request, send_file, jsonify
from rembg import remove, new_session

app = Flask(__name__)

session = new_session("isnet-general-use")

@app.route("/")
def health():
    return {"ok": True}

def resize_if_needed(input_bytes: bytes, max_side: int = 1600) -> bytes:
    image = Image.open(io.BytesIO(input_bytes)).convert("RGBA")
    w, h = image.size
    longest = max(w, h)

    if longest <= max_side:
        out = io.BytesIO()
        image.save(out, format="PNG")
        return out.getvalue()

    scale = max_side / float(longest)
    new_w = int(w * scale)
    new_h = int(h * scale)

    image = image.resize((new_w, new_h), Image.LANCZOS)

    out = io.BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()

@app.post("/remove-bg")
def remove_bg():
    if "image" not in request.files:
        return jsonify({"error": "missing image"}), 400

    file = request.files["image"]
    input_bytes = file.read()

    if not input_bytes:
        return jsonify({"error": "empty image"}), 400

    prepared_bytes = resize_if_needed(input_bytes, max_side=1600)

    output_bytes = remove(
        prepared_bytes,
        session=session,
        alpha_matting=True,
        alpha_matting_foreground_threshold=240,
        alpha_matting_background_threshold=10,
        alpha_matting_erode_size=10,
    )

    return send_file(
        io.BytesIO(output_bytes),
        mimetype="image/png"
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)