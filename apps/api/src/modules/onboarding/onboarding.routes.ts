import { Router } from "express"; 
import { requireAuth } from "../../middleware/require-auth"; 
import { getMyOnboardingStatus } from "./onboarding.controller"; 

const router = Router(); 
   router.get("/me/onboarding-status", requireAuth, getMyOnboardingStatus); 

export default router;
