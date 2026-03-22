import type { Request, Response, NextFunction } from "express";
import { invitationsService } from "./invitations.service";
import type { CreateInvitationRequest, AcceptInvitationRequest } from "@dcapx/contracts";

export async function createInvitation(req: Request, res: Response, next: NextFunction) {
  try {
    const invitedByUserId = req.auth!.userId;
    const body = req.body as CreateInvitationRequest;
    const result = await invitationsService.createInvitation(invitedByUserId, body);
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function getInvitationByToken(req: Request, res: Response, next: NextFunction) {
  try {
    const { token } = req.params;
    const result = await invitationsService.getInvitationByToken(token);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function acceptInvitation(req: Request, res: Response, next: NextFunction) {
  try {
    const { token } = req.params;
    const acceptedUserId = req.auth!.userId;
    const body = req.body as AcceptInvitationRequest;
    const result = await invitationsService.acceptInvitation(token, acceptedUserId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}
