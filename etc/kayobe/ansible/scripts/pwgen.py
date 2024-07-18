import random
import string
import re

# The password requirements required by Wazuh (wazuh/framework/wazuh/security.py)
valid_password = re.compile(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$')

# Generate a random password containg at least one of each: 
# special character, digit, lowercase letter, uppercase letter
def pw_gen(pw_len):
    random_pass = ([random.choice("@$!%*?&-_"),
                    random.choice(string.digits),
                    random.choice(string.ascii_lowercase),
                    random.choice(string.ascii_uppercase),
                    ]
                    + [random.choice(string.ascii_lowercase
                                    + string.ascii_uppercase
                                    + "@$!%*?&-_"
                                    + string.digits) for i in range(pw_len)])

    random.shuffle(random_pass)
    random_pass = ''.join(random_pass)
    return random_pass

# Check if the generated password meets the requirements
def check_user_password(password):
    if valid_password.match(password):
        return True
    else:
        return False

# Generate a password
random_password = pw_gen(30)

# Check if the generated password meets the requirements
# if not, keep generating a new password until it does
while not check_user_password(random_password):
    #print("Password does not meet the requirements, creating a new one...")
    random_password = pw_gen(30)
else:
    print(random_password)
