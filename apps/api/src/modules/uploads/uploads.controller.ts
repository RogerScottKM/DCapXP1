import type { Request, Response, NextFunction } from "express";
import { uploadsService } from "./uploads.service";
import type { PresignUploadRequest, CompleteKycUploadRequest } from "@dcapx/contracts";

export async function presignUpload(req: Request, res: Response, next: NextFunction) {
  try {
    const userId = req.auth!.userId;
    const body = req.body as PresignUploadRequest;
    const result = await uploadsService.presignUpload(body, userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function completeKycUpload(req: Request, res: Response, next: NextFunction) {
  try {
    const userId = req.auth!.userId;
    const body = req.body as CompleteKycUploadRequest;
    const result = await uploadsService.completeKycUpload(body, userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}
