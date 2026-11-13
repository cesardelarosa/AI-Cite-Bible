import argparse
from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F
from transformers import AutoModel, AutoTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType


class SentenceEncoderONNX(nn.Module):
    """Envoltorio que integra Transformer, Mean Pooling y Normalización L2 en el grafo ONNX."""

    def __init__(self, model_name: str):
        super().__init__()
        self.transformer = AutoModel.from_pretrained(model_name)

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        outputs = self.transformer(input_ids=input_ids, attention_mask=attention_mask)
        token_embeddings = outputs[0]
        mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
        sum_embeddings = torch.sum(token_embeddings * mask_expanded, dim=1)
        sum_mask = torch.clamp(mask_expanded.sum(dim=1), min=1e-9)
        mean_pooled = sum_embeddings / sum_mask
        return F.normalize(mean_pooled, p=2, dim=1)


def main():
    root_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Exporta cualquier modelo HuggingFace / SentenceTransformer local a ONNX + INT8"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        help="ID de HuggingFace o ruta a carpeta local afinada",
    )
    parser.add_argument("--out-dir", type=Path, default=root_dir / "models")
    parser.add_argument("--opset", type=int, default=17)
    parser.add_argument("--no-quantize", action="store_true")
    parser.add_argument(
        "--sample-text",
        type=str,
        default="Texto de prueba para trazado del grafo ONNX",
    )
    args = parser.parse_args()

    models_dir = args.out_dir
    models_dir.mkdir(parents=True, exist_ok=True)

    fp32_onnx_path = models_dir / "encoder_fp32.onnx"
    int8_onnx_path = models_dir / "encoder_int8.onnx"

    print(f"Guardando tokenizer.json desde {args.model}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    tokenizer.save_pretrained(str(models_dir))

    print("Cargando modelo y fusionando Pooling + L2...")
    model = SentenceEncoderONNX(args.model)
    model.eval()

    dummy_inputs = tokenizer(args.sample_text, return_tensors="pt")

    print(f"Exportando a ONNX FP32 (opset {args.opset})...")
    torch.onnx.export(
        model,
        (dummy_inputs["input_ids"], dummy_inputs["attention_mask"]),
        str(fp32_onnx_path),
        input_names=["input_ids", "attention_mask"],
        output_names=["sentence_embedding"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence_length"},
            "attention_mask": {0: "batch_size", 1: "sequence_length"},
            "sentence_embedding": {0: "batch_size"},
        },
        opset_version=args.opset,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"ONNX FP32 generado: {fp32_onnx_path.stat().st_size / (1024*1024):.2f} MB")

    if not args.no_quantize:
        print("Cuantizando a INT8 dinámico...")
        quantize_dynamic(
            model_input=fp32_onnx_path,
            model_output=int8_onnx_path,
            weight_type=QuantType.QUInt8,
        )
        print(f"ONNX INT8 generado: {int8_onnx_path.stat().st_size / (1024*1024):.2f} MB")

    print(f"Tokenizer en: {models_dir / 'tokenizer.json'}")


if __name__ == "__main__":
    main()
