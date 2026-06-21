$AccountPolicy | Select @{n="PolicyType";e={"Account Lockout"}},`

                            DistinguishedName,`

                            @{n="lockoutDuration";e={"$($_.lockoutDuration / -600000000) minutes"}},`

                            @{n="lockoutObservationWindow";e={"$($_.lockoutObservationWindow / -600000000) minutes"}},`

                            lockoutThreshold | Format-List