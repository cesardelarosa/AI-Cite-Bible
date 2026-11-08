from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F
from transformers import AutoModel, AutoTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType

# Envoltorio que integra Transformer, Mean Pooling y Normalizacion L2 en el grafo ONNX
class SentenceEncoderONNX(nn.Module):
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

# Exportacion del grafo y cuantizacion dinamica a INT8
def main():
    root_dir = Path(__file__).resolve().parent.parent
    models_dir = root_dir / "models"
    models_dir.mkdir(parents=True, exist_ok=True)

    model_name = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    fp32_onnx_path = models_dir / "encoder_fp32.onnx"
    int8_onnx_path = models_dir / "encoder_int8.onnx"

    print("Guardando tokenizer.json...")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    tokenizer.save_pretrained(str(models_dir))

    print("Cargando modelo y fusionando Pooling + L2...")
    model = SentenceEncoderONNX(model_name)
    model.eval()

    dummy_inputs = tokenizer(
        "Texto de prueba para trazado del grafo ONNX",
        return_tensors="pt"
    )

    print("Exportando a ONNX FP32...")
    torch.onnx.export(
        model,
        (dummy_inputs["input_ids"], dummy_inputs["attention_mask"]),
        str(fp32_onnx_path),
        input_names=["input_ids", "attention_mask"],
        output_names=["sentence_embedding"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence_length"},
            "attention_mask": {0: "batch_size", 1: "sequence_length"},
            "sentence_embedding": {0: "batch_size"}
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False
    )

    print("Cuantizando a INT8 dinamico...")
    quantize_dynamic(
        model_input=fp32_onnx_path,
        model_output=int8_onnx_path,
        weight_type=QuantType.QUInt8
    )

    print(f"ONNX FP32 generado: {fp32_onnx_path.stat().st_size / (1024*1024):.2f} MB")
    print(f"ONNX INT8 generado: {int8_onnx_path.stat().st_size / (1024*1024):.2f} MB")
    print(f"Tokenizer en: {models_dir / 'tokenizer.json'}")

if __name__ == "__main__":
    main()
