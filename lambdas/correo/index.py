import json


def handler(event, context):
    """Arma y envia la entrada por correo (simulado)."""
    for registro in event["Records"]:
        orden = json.loads(registro["body"])

        # TODO: generar el QR y enviar el correo con Amazon SES
        print(f"Entrada enviada (simulado) para la orden {orden['orden_id']}")

    return {"statusCode": 200}
