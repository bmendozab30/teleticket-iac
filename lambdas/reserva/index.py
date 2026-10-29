import json
import os
import uuid

import boto3
from botocore.exceptions import ClientError

sqs = boto3.client("sqs")
dynamodb = boto3.client("dynamodb")

COLA_ORDENES_URL = os.environ["COLA_ORDENES_URL"]
TABLA_RESERVAS = os.environ["TABLA_RESERVAS"]


def handler(event, context):
    usuario = event.get("usuario", "usuario-demo")
    asiento = event.get("asiento", "A1")
    orden_id = str(uuid.uuid4())

    # Escritura condicional: solo guarda si el asiento esta libre
    try:
        dynamodb.put_item(
            TableName=TABLA_RESERVAS,
            Item={
                "asiento_id": {"S": asiento},
                "orden_id": {"S": orden_id},
                "usuario": {"S": usuario},
                "estado": {"S": "RESERVADO"},
            },
            ConditionExpression="attribute_not_exists(asiento_id)",
        )
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            print(f"Asiento {asiento} ocupado")
            return {
                "statusCode": 409,
                "body": json.dumps({"mensaje": "asiento ocupado"}),
            }
        raise

    orden = {"orden_id": orden_id, "usuario": usuario, "asiento": asiento}

    sqs.send_message(
        QueueUrl=COLA_ORDENES_URL,
        MessageBody=json.dumps(orden),
        MessageGroupId="ordenes",
        MessageDeduplicationId=orden_id,
    )

    print(f"Orden recibida: {orden}")
    return {
        "statusCode": 200,
        "body": json.dumps({"mensaje": "orden recibida", "orden_id": orden_id}),
    }