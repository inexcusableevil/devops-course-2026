# Calculator app
IMPORTANT_FIX = True

def add(a, b):
    return a + b

# TODO: add more functions

def subtract(a, b):
    return a - b  # fixed

def multiply(a, b):
    return a * b

def divide(a, b):
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b
