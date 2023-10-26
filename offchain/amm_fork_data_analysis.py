import io
import os
import pandas as pd
import plotly.subplots as sp
import plotly.graph_objs as go
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Read data from csv file from env
filepath = os.environ['UNISWAP_SWETH_FILE_PATH']
print("Reading data from file: " + filepath)
df = pd.read_csv(filepath)

# Convert all columns to numeric types
df = df.apply(pd.to_numeric, errors='coerce')
df = df / 1e18

# Compute percent difference and effective swap rate
df['PercentDifference'] = ((df['newPrice'] - df['oldPrice']) / df['oldPrice']) * 100
df['EffectiveSwapRate'] = df['amountSpecified'] / df['swapReceived']

# Create subplots
fig = sp.make_subplots(rows=1, cols=2, subplot_titles=('Amount Swapped vs Price Change Percent Difference', 'Amount Swapped vs Swap Tokens Returned'))

# Add traces to subplots
trace1 = go.Scatter(x=df['amountSpecified'], y=df['PercentDifference'], mode='markers', name='Percent Difference')
trace2 = go.Scatter(x=df['amountSpecified'], y=df['EffectiveSwapRate'], mode='markers', name='Swap Tokens Returned')

fig.add_trace(trace1, row=1, col=1)
fig.add_trace(trace2, row=1, col=2)

# Update subplot layout
fig.update_layout(title_text='Data Analysis', showlegend=False)

# Save the combined plot as an HTML file
fig.write_html('./offchain/files/output.html')
print("Combined HTML file generated successfully: ./offchain/files/output.html")

# clear the output csv file
open(filepath, 'w').close()