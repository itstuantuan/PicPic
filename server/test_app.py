import asyncio
import base64
import json
import httpx
import io
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image
import app


class ServiceTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.enterContext(patch.object(app,"DB",Path(directory.name)/"jobs.sqlite"))
        self.enterContext(patch.dict(os.environ, {"GEMINI_API_KEY":"test-only","GEMINI_EDIT_MODEL":"test-model","USER_DAILY_LIMIT":"3"}))
        self.uid = "owner1"
        app.app.dependency_overrides[app.owner] = lambda: self.uid
        self.addCleanup(app.app.dependency_overrides.clear)
        self.real_generate=app.generate
        self.calls=0

        async def model(row):
            self.calls += 1
            await asyncio.sleep(.01)
            if self.calls == 1:
                raise ValueError("provider test failure")
            return row["source"], None

        self.enterContext(patch.object(app,"generate",model))
        self.client=self.enterContext(TestClient(app.app))
        self.path="/jobs/"+str(uuid4())
        buffer=io.BytesIO()
        Image.new("RGB",(20,20)).save(buffer,format="PNG")
        self.photo=buffer.getvalue()

    def create(self):
        return self.client.post(self.path,params={"kind":"edit","style":"Vintage"},content=self.photo)

    def wait(self):
        for _ in range(80):
            data=self.client.get(self.path).json()
            if data["state"] in ("failed","done"):
                return data
            time.sleep(.05)
        self.fail("worker did not finish")

    def test_state_retry_and_isolation(self):
        self.assertEqual(self.create().status_code,200)
        self.assertEqual(self.wait()["state"],"failed")
        self.assertEqual(self.create().json()["attempt"],1)
        retry=self.path+"/retry?attempt=1"
        self.assertEqual(self.client.post(retry).json()["attempt"],2)
        self.assertEqual(self.client.post(retry).json()["attempt"],2)
        self.assertEqual(self.wait()["state"],"done")
        self.assertEqual(self.calls,2)
        self.assertEqual(self.client.get(self.path+"/image/result").headers["content-type"],"image/jpeg")
        self.assertEqual(len(self.client.get("/jobs").json()),1)
        self.uid="owner2"
        self.assertEqual(self.client.get("/jobs").json(),[])
        self.assertEqual(self.client.get(self.path+"/image/source").status_code,404)
        self.assertEqual(self.client.post(retry).status_code,404)

    def test_gemini_contract_with_local_transport(self):
        sent=[]
        def provider(req):
            body=json.loads(req.content)
            sent.append(body)
            encoded=base64.b64encode(self.photo).decode()
            part={"inlineData":{"mimeType":"image/png","data":encoded}} if len(sent)==1 else {"text":json.dumps("公园")}
            return httpx.Response(200,json={"candidates":[{"content":{"parts":[part]}}]})
        factory=httpx.AsyncClient
        def client(**kwargs):
            return factory(transport=httpx.MockTransport(provider),**kwargs)
        with patch.object(app.httpx,"AsyncClient",client), patch.dict(os.environ,{"GEMINI_SCENE_MODEL":"test-model"}):
            real_generate=self.real_generate
            row={"kind":"edit","style":"Vintage","prompt":"柔和光线","source":self.photo}
            result,scene=asyncio.run(real_generate(row))
            self.assertEqual(Image.open(io.BytesIO(result)).format,"JPEG")
            self.assertIsNone(scene)
            self.assertEqual(asyncio.run(real_generate({**row,"kind":"scene"})),(None,"公园"))
            self.assertIn("inlineData",sent[0]["contents"][0]["parts"][1])
            self.assertIn("IMAGE",sent[0]["generationConfig"]["responseModalities"])
            self.assertIn("公园",sent[1]["generationConfig"]["responseSchema"]["enum"])

    def test_missing_config_and_bad_upload(self):
        with patch.dict(os.environ,{"GEMINI_API_KEY":""}):
            self.assertEqual(self.create().status_code,503)
        self.assertEqual(self.client.post(self.path+"?kind=edit&style=Vintage",content=b"invalid").status_code,422)
        self.assertEqual(self.client.get("/jobs").json(),[])
