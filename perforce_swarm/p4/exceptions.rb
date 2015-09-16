module PerforceSwarm
  module P4
    class LoginException < RuntimeError
    end

    class IdentityNotFound < LoginException
    end

    class IdentityAmbiguous < LoginException
    end

    class CredentialInvalid < LoginException
    end
  end
end