import json
import os

import boto3
from botocore.exceptions import ClientError

sqs = boto3.client("sqs")
dynamodb = boto3.client("dynamodb")

COLA_CORREO_URL = os.environ["COLA_CORREO_URL"]
TABLA_RESERVAS = os.environ["TABLA_RESERVAS"]


def handler(event, context):
    for registro in event["Records"]:
        orden = json.loads(registro["body"])

        # Confirma la venta solo si el asiento sigue RESERVADO
        try:
            dynamodb.update_item(
                TableName=TABLA_RESERVAS,
                Key={"asiento_id": {"S": orden["asiento"]}},
                UpdateExpression="SET estado = :pagado",
                ConditionExpression="estado = :reservado",
                ExpressionAttributeValues={
                    ":pagado": {"S": "PAGADO"},
                    ":reservado": {"S": "RESERVADO"},
                },
            )
        except ClientError as error:
            if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
                print(f"Orden {orden['orden_id']} ya estaba pagada; se omite")
                continue
            raise

        print(f"Cobro simulado aprobado para la orden {orden['orden_id']}")

        sqs.send_message(
            QueueUrl=COLA_CORREO_URL,
            MessageBody=json.dumps(orden),
        )

    return {"statusCode": 200}