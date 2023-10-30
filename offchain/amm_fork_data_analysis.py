import io
import os
from dotenv import load_dotenv
import pandas as pd
import plotly.subplots as sp
import plotly.graph_objects as go

# Load environment variables
load_dotenv()

# Read data from csv file from env
filepath = os.environ['UNISWAP_SWETH_FILE_PATH']
print("Reading data from file: " + filepath)
# Read the first line of the CSV file to get balances
with open(filepath, 'r') as file:
    first_line = file.readline().strip()  # Read the first line and remove newline characters
    swEth_balance, eth_balance = first_line.split(',')  # Split the line into two values using a comma
df = pd.read_csv(filepath, skiprows=1)

# Convert all columns to numeric types
df = df.apply(pd.to_numeric, errors='coerce') / 1e18
swEth_balance = float(swEth_balance) / 1e18
eth_balance = float(eth_balance) / 1e18

# Compute percent difference and effective swap rate
df['PercentDifference'] = ((df['newPrice'] - df['oldPrice']) / df['oldPrice']) * 100
df['EffectiveSwapRate'] = df['swapReceived'] / df['amountSpecified']

# Create subplots layout
fig = sp.make_subplots(rows=3, cols=2, 
                       subplot_titles=('ETH Swapped vs Price Change Percent Difference',
                                       'ETH Swapped vs Effective Swap Rate',
                                       'ETH Swapped vs. swETH Post-Swap Volume',
                                       'ETH Swapped vs. ETH Post-Swap Volume',
                                       'ETH Swapped vs Swap Tokens Returned', 
                                       'Current swETH Pool Balance & ETH Pool Balance'))

# Add scatter plots to the subplots
scatter_fig1 = go.Scatter(x=df['amountSpecified'], y=df['PercentDifference'], mode='lines+markers', name='Percent Difference')
scatter_fig2 = go.Scatter(x=df['amountSpecified'], y=df['EffectiveSwapRate'], mode='lines+markers', name='Effective Swap Rate')
scatter_fig3 = go.Scatter(x=df['amountSpecified'], y=df['ethInPool'], mode='lines+markers', name='ETH In Pool')
scatter_fig4 = go.Scatter(x=df['amountSpecified'], y=df['swEthInPool'], mode='lines+markers', name='swETH in Pool')
scatter_fig5 = go.Scatter(x=df['amountSpecified'], y=df['swapReceived'], mode='lines+markers', name='Swap Tokens Returned')

# Label axes and add traces to subplots
fig.add_trace(scatter_fig1, row=1, col=1)
fig.add_trace(scatter_fig2, row=1, col=2)
fig.add_trace(scatter_fig3, row=2, col=1)
fig.add_trace(scatter_fig4, row=2, col=2)
fig.add_trace(scatter_fig5, row=3, col=1)
fig.update_xaxes(title_text='ETH', row=1, col=1)
fig.update_xaxes(title_text='ETH', row=1, col=2)
fig.update_xaxes(title_text='ETH', row=2, col=1)
fig.update_xaxes(title_text='ETH', row=2, col=2)
fig.update_xaxes(title_text='ETH', row=3, col=1)
fig.update_yaxes(title_text='Percent Difference (%)', row=1, col=1)
fig.update_yaxes(title_text='Effective Swap Rate (swETH/ETH)', row=1, col=2)
fig.update_yaxes(title_text='# of Tokens', row=2, col=1)
fig.update_yaxes(title_text='# of Tokens', row=2, col=2)
fig.update_yaxes(title_text='swETH (EAT)', row=3, col=1)


# Add bar charts for current balance in pool
bar_fig1 = go.Bar(x=['swETH Balance', 'ETH Balance'], y=[swEth_balance, eth_balance])
fig.add_trace(bar_fig1, row=3, col=2)
fig.update_yaxes(title_text='# of Tokens', row=3, col=2)

# Update layout for the combined dashboard
fig.update_layout(title_text='Data Analysis Dashboard', showlegend=False)
# Save the dashboard as an HTML file
fig.write_html('./offchain/files/output.html')
print("Combined HTML file generated successfully: ./offchain/files/output.html")

# clear the output csv file
# open(filepath, 'w').close()