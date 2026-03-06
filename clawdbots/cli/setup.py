from setuptools import setup

setup(
    name="clawdbot",
    version="0.1.0",
    py_modules=["clawdbot"],
    entry_points={
        "console_scripts": [
            "clawdbot=clawdbot:main",
        ],
    },
    python_requires=">=3.10",
)
